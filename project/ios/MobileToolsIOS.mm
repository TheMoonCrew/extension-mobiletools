#include "MobileToolsIOS.h"

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Contacts/Contacts.h>
#import <CoreHaptics/CoreHaptics.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <EventKit/EventKit.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <MediaPlayer/MediaPlayer.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>

#include <cstdlib>
#include <string>
#include <vector>
#include <sys/utsname.h>

// Compiled with ARC (see mobiletools_ios.xml).

// Must match mobiletools.PermissionStatus
enum
{
	StatusNotDetermined = 0,
	StatusGranted = 1,
	StatusDenied = 2,
	StatusDeniedPermanently = 3,
	StatusRestricted = 4
};

#pragma mark - Helpers

static NSString* toNSString(const char* value)
{
	return value ? [NSString stringWithUTF8String:value] : @"";
}

static void runOnMain(dispatch_block_t block)
{
	if ([NSThread isMainThread])
		block();
	else
		dispatch_async(dispatch_get_main_queue(), block);
}

static UIWindow* findKeyWindow()
{
	UIApplication* application = [UIApplication sharedApplication];

	if (@available(iOS 13.0, *))
	{
		for (UIScene* scene in application.connectedScenes)
		{
			if (![scene isKindOfClass:[UIWindowScene class]])
				continue;

			for (UIWindow* window in ((UIWindowScene*)scene).windows)
			{
				if (window.isKeyWindow)
					return window;
			}
		}
	}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	// Apps without scenes (the usual Lime/SDL setup) only have the legacy key window.
	return application.keyWindow ?: application.windows.firstObject;
#pragma clang diagnostic pop
}

#pragma mark - Pending permission requests

// Permission ids whose system prompt is currently showing. Completion handlers run on arbitrary
// queues, so every access goes through @synchronized.
static NSMutableSet<NSString*>* pendingRequests()
{
	static NSMutableSet<NSString*>* requests;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ requests = [NSMutableSet set]; });
	return requests;
}

static void setPending(NSString* permission, BOOL pending)
{
	NSMutableSet* requests = pendingRequests();

	@synchronized(requests)
	{
		if (pending)
			[requests addObject:permission];
		else
			[requests removeObject:permission];
	}
}

static BOOL isPending(NSString* permission)
{
	NSMutableSet* requests = pendingRequests();

	@synchronized(requests)
	{
		return [requests containsObject:permission];
	}
}

#pragma mark - Location

static int mapLocationStatus(CLAuthorizationStatus status)
{
	switch (status)
	{
		case kCLAuthorizationStatusNotDetermined: return StatusNotDetermined;
		case kCLAuthorizationStatusRestricted: return StatusRestricted;
		case kCLAuthorizationStatusDenied: return StatusDeniedPermanently;
		case kCLAuthorizationStatusAuthorizedAlways:
		case kCLAuthorizationStatusAuthorizedWhenInUse: return StatusGranted;
	}

	return StatusNotDetermined;
}

static int locationStatus()
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	// The class method is deprecated in iOS 14 but, unlike the instance property, doesn't need a manager.
	return mapLocationStatus([CLLocationManager authorizationStatus]);
#pragma clang diagnostic pop
}

static NSString* const kAskedAlwaysKey = @"mobiletools.asked.location_always";

static int locationAlwaysStatus()
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	CLAuthorizationStatus current = [CLLocationManager authorizationStatus];
#pragma clang diagnostic pop

	switch (current)
	{
		case kCLAuthorizationStatusAuthorizedAlways:
			return StatusGranted;

		case kCLAuthorizationStatusAuthorizedWhenInUse:
			// iOS offers the upgrade to "always" once, so it is only final after we asked.
			return [[NSUserDefaults standardUserDefaults] boolForKey:kAskedAlwaysKey] ? StatusDeniedPermanently : StatusNotDetermined;

		default:
			return locationStatus();
	}
}

@interface MTLocationDelegate : NSObject <CLLocationManagerDelegate>
@end

@implementation MTLocationDelegate

// iOS 14+
- (void)locationManagerDidChangeAuthorization:(CLLocationManager*)manager
{
	[self authorizationChanged];
}

// iOS 13 and older
- (void)locationManager:(CLLocationManager*)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
	[self authorizationChanged];
}

- (void)authorizationChanged
{
	// The delegate is also called once with the current state when it is attached.
	if (locationStatus() != StatusNotDetermined)
		setPending(@"location", NO);

	// Reaching "always", or being refused outright, is final. Keeping "while using" at the upgrade
	// prompt doesn't call the delegate at all, which is what the app-became-active handling below covers.
	if (locationAlwaysStatus() == StatusGranted || locationStatus() == StatusDeniedPermanently)
		setPending(@"location_always", NO);
}

@end

static CLLocationManager* locationManager;
static MTLocationDelegate* locationDelegate;

#pragma mark - Camera / microphone / images / audio / notifications

static int mapAVStatus(AVAuthorizationStatus status)
{
	switch (status)
	{
		case AVAuthorizationStatusNotDetermined: return StatusNotDetermined;
		case AVAuthorizationStatusRestricted: return StatusRestricted;
		case AVAuthorizationStatusDenied: return StatusDeniedPermanently;
		case AVAuthorizationStatusAuthorized: return StatusGranted;
	}

	return StatusNotDetermined;
}

static int imagesStatus()
{
	NSInteger status;

	if (@available(iOS 14.0, *))
		status = (NSInteger)[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
	else
		status = (NSInteger)[PHPhotoLibrary authorizationStatus];

	// PHAuthorizationStatus: 0 notDetermined, 1 restricted, 2 denied, 3 authorized, 4 limited (iOS 14+)
	switch (status)
	{
		case 0: return StatusNotDetermined;
		case 1: return StatusRestricted;
		case 2: return StatusDeniedPermanently;
		default: return StatusGranted;
	}
}

static int audioStatus()
{
	// MPMediaLibraryAuthorizationStatus: 0 notDetermined, 1 denied, 2 restricted, 3 authorized
	switch ((NSInteger)[MPMediaLibrary authorizationStatus])
	{
		case 0: return StatusNotDetermined;
		case 1: return StatusDeniedPermanently;
		case 2: return StatusRestricted;
		default: return StatusGranted;
	}
}

static int notificationsStatus()
{
	// The settings are only available asynchronously, so wait briefly for them. The handler is
	// documented to run on a background queue, which keeps this from deadlocking the main thread.
	__block int result = StatusNotDetermined;
	dispatch_semaphore_t done = dispatch_semaphore_create(0);

	[[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings)
	{
		// UNAuthorizationStatus: 0 notDetermined, 1 denied, 2 authorized, 3 provisional, 4 ephemeral
		switch ((NSInteger)settings.authorizationStatus)
		{
			case 0: result = StatusNotDetermined; break;
			case 1: result = StatusDeniedPermanently; break;
			default: result = StatusGranted; break;
		}

		dispatch_semaphore_signal(done);
	}];

	dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC));
	return result;
}

#pragma mark - Tracking

static int trackingStatus()
{
	if (@available(iOS 14.0, *))
	{
		// ATTrackingManagerAuthorizationStatus: 0 notDetermined, 1 restricted, 2 denied, 3 authorized
		switch ((NSInteger)[ATTrackingManager trackingAuthorizationStatus])
		{
			case 0: return StatusNotDetermined;
			case 1: return StatusRestricted;
			case 2: return StatusDeniedPermanently;
			default: return StatusGranted;
		}
	}

	// Before iOS 14 there was nothing to ask.
	return StatusGranted;
}

#pragma mark - Bluetooth

static int bluetoothStatus()
{
	if (@available(iOS 13.1, *))
	{
		// CBManagerAuthorization: 0 notDetermined, 1 restricted, 2 denied, 3 allowedAlways
		switch ((NSInteger)[CBCentralManager authorization])
		{
			case 0: return StatusNotDetermined;
			case 1: return StatusRestricted;
			case 2: return StatusDeniedPermanently;
			default: return StatusGranted;
		}
	}

	// Before iOS 13 there was no Bluetooth permission.
	return StatusGranted;
}

@interface MTBluetoothDelegate : NSObject <CBCentralManagerDelegate>
@end

@implementation MTBluetoothDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager*)central
{
	// Called once when the manager is created, and again after the user answered the prompt.
	if (bluetoothStatus() != StatusNotDetermined)
		setPending(@"bluetooth", NO);
}

@end

static CBCentralManager* bluetoothManager;
static MTBluetoothDelegate* bluetoothDelegate;

#pragma mark - Contacts / calendar / motion / biometrics

// CNAuthorizationStatus and EKAuthorizationStatus share their first values:
// 0 notDetermined, 1 restricted, 2 denied, 3 authorized.
static int mapEntityStatus(NSInteger status)
{
	switch (status)
	{
		case 0: return StatusNotDetermined;
		case 1: return StatusRestricted;
		case 2: return StatusDeniedPermanently;
		default: return StatusGranted; // 3 authorized, 4 limited access (contacts, iOS 18)
	}
}

static int calendarStatus()
{
	NSInteger status = (NSInteger)[EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];

	// 4 is "write only" (iOS 17): events can be added but not read, which is not what we report as granted.
	return status == 4 ? StatusDeniedPermanently : mapEntityStatus(status);
}

static int motionStatus()
{
	if (![CMMotionActivityManager isActivityAvailable])
		return StatusRestricted;

	if (@available(iOS 11.0, *))
		return mapEntityStatus((NSInteger)[CMMotionActivityManager authorizationStatus]);

	return StatusGranted;
}

static int biometricsStatus()
{
	LAContext* context = [[LAContext alloc] init];
	NSError* error = nil;

	if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error])
		return StatusGranted;

	// LAError codes: -6 biometryNotAvailable, -7 biometryNotEnrolled, -8 biometryLockout
	switch (error.code)
	{
		case -7:
		case -8:
			return StatusDenied;

		case -6:
		{
			// "Not available" covers both a missing sensor and Face ID refused for this app.
			BOOL hasSensor = NO;

			if (@available(iOS 11.0, *))
				hasSensor = context.biometryType != LABiometryTypeNone;

			return hasSensor ? StatusDeniedPermanently : StatusRestricted;
		}

		default:
			return StatusRestricted;
	}
}

#pragma mark - Haptic patterns

struct HapticEvent
{
	double time;      // milliseconds
	double duration;  // milliseconds, 0 for a transient tap
	double intensity; // 0-1
	double sharpness; // 0-1
};

static NSUInteger hapticGeneration = 0; // bumped to cancel ticks still queued by the fallback
static id hapticEngine = nil;           // CHHapticEngine, kept as id so this compiles for older deployment targets
static id hapticPlayer = nil;           // id<CHHapticPatternPlayer>

// text: "time:duration:intensity:sharpness" joined by commas, see HapticPattern.toCompact().
static std::vector<HapticEvent> parseHapticEvents(const char* text)
{
	std::vector<HapticEvent> events;

	for (NSString* item in [toNSString(text) componentsSeparatedByString:@","])
	{
		NSArray<NSString*>* parts = [item componentsSeparatedByString:@":"];

		// The pattern is capped on the Haxe side, this only protects against corrupt input.
		if (parts.count != 4 || events.size() >= 512)
			continue;

		events.push_back({ parts[0].doubleValue, parts[1].doubleValue, parts[2].doubleValue, parts[3].doubleValue });
	}

	return events;
}

static BOOL coreHapticsSupported()
{
	if (@available(iOS 13.0, *))
		return [CHHapticEngine capabilitiesForHardware].supportsHaptics;

	return NO;
}

// Devices without Core Haptics (older iPhones, iPads) only have the impact generators, so tap once per event.
static void playHapticFallback(const std::vector<HapticEvent>& events)
{
	NSUInteger generation = hapticGeneration;

	for (const HapticEvent& event : events)
	{
		// A held vibration becomes a run of ticks, since the generators cannot sustain.
		int ticks = event.duration > 0 ? MAX(1, (int)(event.duration / 60)) : 1;
		int style = event.intensity > 0.66 ? 2 : (event.intensity > 0.33 ? 1 : 0);

		for (int i = 0; i < ticks; i++)
		{
			double delay = (event.time + i * 60) / 1000.0;

			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				if (generation == hapticGeneration)
					mobiletools::ios::impact(style);
			});
		}
	}
}

API_AVAILABLE(ios(13.0))
static BOOL playHapticCore(const std::vector<HapticEvent>& events)
{
	NSError* error = nil;
	CHHapticEngine* engine = hapticEngine;

	if (engine == nil)
	{
		engine = [[CHHapticEngine alloc] initAndReturnError:&error];

		if (engine == nil)
			return NO;

		engine.autoShutdownEnabled = YES;

		// The system stops the engine when the app is backgrounded or audio is interrupted: bring it back when asked to.
		__weak CHHapticEngine* weakEngine = engine;
		engine.resetHandler = ^{ [weakEngine startAndReturnError:nil]; };

		hapticEngine = engine;
	}

	if (![engine startAndReturnError:&error])
		return NO;

	NSMutableArray<CHHapticEvent*>* chEvents = [NSMutableArray array];

	for (const HapticEvent& event : events)
	{
		CHHapticEventParameter* intensity = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity value:(float)event.intensity];
		CHHapticEventParameter* sharpness = [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness value:(float)event.sharpness];

		CHHapticEvent* chEvent = event.duration > 0
			? [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous parameters:@[ intensity, sharpness ] relativeTime:event.time / 1000.0 duration:event.duration / 1000.0]
			: [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient parameters:@[ intensity, sharpness ] relativeTime:event.time / 1000.0];

		[chEvents addObject:chEvent];
	}

	CHHapticPattern* pattern = [[CHHapticPattern alloc] initWithEvents:chEvents parameters:@[] error:&error];

	if (pattern == nil)
		return NO;

	id<CHHapticPatternPlayer> player = [engine createPlayerWithPattern:pattern error:&error];

	if (player == nil)
		return NO;

	// A new pattern replaces the one still playing.
	[(id<CHHapticPatternPlayer>)hapticPlayer stopAtTime:0 error:nil];
	hapticPlayer = player;

	return [player startAtTime:0 error:&error];
}

#pragma mark - Public interface

namespace mobiletools
{
	namespace ios
	{
		void showToast(const char* message, int duration)
		{
			NSString* text = toNSString(message);

			runOnMain(^{
				UIWindow* window = findKeyWindow();

				if (window == nil || text.length == 0)
					return;

				UILabel* label = [[UILabel alloc] init];
				label.text = text;
				label.numberOfLines = 0;
				label.textAlignment = NSTextAlignmentCenter;
				label.textColor = [UIColor whiteColor];
				label.font = [UIFont systemFontOfSize:14];
				label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
				label.layer.cornerRadius = 12;
				label.layer.masksToBounds = YES;
				label.userInteractionEnabled = NO;

				CGFloat maxWidth = window.bounds.size.width * 0.8;
				CGSize size = [label sizeThatFits:CGSizeMake(maxWidth - 24, CGFLOAT_MAX)];
				CGFloat width = MIN(size.width + 24, maxWidth);
				CGFloat height = size.height + 16;
				CGFloat bottomInset = 0;

				if (@available(iOS 11.0, *))
					bottomInset = window.safeAreaInsets.bottom;

				label.frame = CGRectMake((window.bounds.size.width - width) / 2, window.bounds.size.height - height - bottomInset - 48, width, height);
				label.alpha = 0;
				[window addSubview:label];

				NSTimeInterval visibleFor = duration == 1 ? 3.5 : 2.0;

				[UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; } completion:^(BOOL finished)
				{
					[UIView animateWithDuration:0.3 delay:visibleFor options:0 animations:^{ label.alpha = 0; } completion:^(BOOL done)
					{
						[label removeFromSuperview];
					}];
				}];
			});
		}

		void vibrate()
		{
			// iOS has no API for custom vibration lengths without Core Haptics, so use the system vibration.
			AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
		}

		void setKeepScreenOn(bool enabled)
		{
			runOnMain(^{ [UIApplication sharedApplication].idleTimerDisabled = enabled; });
		}

		const char* getDeviceInfo()
		{
			static std::string json;

			struct utsname system;
			uname(&system);

			// On the simulator the machine name is the host CPU, so prefer the simulated device.
			const char* simulated = getenv("SIMULATOR_MODEL_IDENTIFIER");
			NSString* model = toNSString(simulated ? simulated : system.machine);
			NSString* version = [UIDevice currentDevice].systemVersion;

			NSDictionary* info = @{
				@"manufacturer": @"Apple",
				@"model": model,
				@"osVersion": version,
				@"apiLevel": @([[[version componentsSeparatedByString:@"."] firstObject] integerValue])
			};

			NSData* data = [NSJSONSerialization dataWithJSONObject:info options:0 error:nil];
			NSString* string = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{}";

			json = string.UTF8String;
			return json.c_str();
		}

		void playHapticPattern(const char* events)
		{
			std::vector<HapticEvent> parsed = parseHapticEvents(events);

			if (parsed.empty())
				return;

			runOnMain(^{
				// Anything the fallback still has queued from an earlier pattern must not play on top of this one.
				hapticGeneration++;

				if (@available(iOS 13.0, *))
				{
					if (coreHapticsSupported() && playHapticCore(parsed))
						return;
				}

				playHapticFallback(parsed);
			});
		}

		void cancelHaptics()
		{
			runOnMain(^{
				hapticGeneration++;

				if (@available(iOS 13.0, *))
					[(id<CHHapticPatternPlayer>)hapticPlayer stopAtTime:0 error:nil];
			});
		}

		int getHapticCapabilities()
		{
			// 1 can vibrate, 2 amplitude control, 4 sharpness control. Core Haptics gives all three.
			if (coreHapticsSupported())
				return 1 | 2 | 4;

			return [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone ? 1 : 0;
		}

		const char* getDirectory(int directory)
		{
			static std::string path;

			// mobiletools.StorageDirectory: 0 internal, 1 app external, 2 shared. iOS only has the app's sandbox.
			NSSearchPathDirectory searchPath = directory == 0 ? NSApplicationSupportDirectory : NSDocumentDirectory;
			NSString* folder = NSSearchPathForDirectoriesInDomains(searchPath, NSUserDomainMask, YES).firstObject;

			if (folder != nil && directory == 0)
			{
				// Application Support is not created automatically.
				[[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
			}

			path = folder != nil ? folder.UTF8String : "";
			return path.c_str();
		}

		void impact(int style)
		{
			runOnMain(^{
				// Generators are cached: creating one per call adds latency, and prepare() wakes the Taptic Engine.
				static NSMutableDictionary<NSNumber*, UIImpactFeedbackGenerator*>* generators;

				if (generators == nil)
					generators = [NSMutableDictionary dictionary];

				UIImpactFeedbackGenerator* generator = generators[@(style)];

				if (generator == nil)
				{
					// mobiletools.ImpactStyle: 0 light, 1 medium, 2 heavy, 3 soft, 4 rigid
					UIImpactFeedbackStyle feedbackStyle = UIImpactFeedbackStyleMedium;

					switch (style)
					{
						case 0: feedbackStyle = UIImpactFeedbackStyleLight; break;
						case 1: feedbackStyle = UIImpactFeedbackStyleMedium; break;
						case 2: feedbackStyle = UIImpactFeedbackStyleHeavy; break;
						case 3:
							if (@available(iOS 13.0, *))
								feedbackStyle = UIImpactFeedbackStyleSoft;
							else
								feedbackStyle = UIImpactFeedbackStyleLight;
							break;
						case 4:
							if (@available(iOS 13.0, *))
								feedbackStyle = UIImpactFeedbackStyleRigid;
							else
								feedbackStyle = UIImpactFeedbackStyleHeavy;
							break;
					}

					generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:feedbackStyle];
					generators[@(style)] = generator;
				}

				[generator impactOccurred];
				[generator prepare];
			});
		}

		void notification(int type)
		{
			runOnMain(^{
				static UINotificationFeedbackGenerator* generator;

				if (generator == nil)
					generator = [[UINotificationFeedbackGenerator alloc] init];

				// mobiletools.NotificationType: 0 success, 1 warning, 2 error
				UINotificationFeedbackType feedbackType = UINotificationFeedbackTypeSuccess;

				if (type == 1)
					feedbackType = UINotificationFeedbackTypeWarning;
				else if (type == 2)
					feedbackType = UINotificationFeedbackTypeError;

				[generator notificationOccurred:feedbackType];
				[generator prepare];
			});
		}

		void selection()
		{
			runOnMain(^{
				static UISelectionFeedbackGenerator* generator;

				if (generator == nil)
					generator = [[UISelectionFeedbackGenerator alloc] init];

				[generator selectionChanged];
				[generator prepare];
			});
		}

		int checkPermission(const char* permission)
		{
			NSString* key = toNSString(permission);

			if ([key isEqualToString:@"camera"])
				return mapAVStatus([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]);

			if ([key isEqualToString:@"microphone"])
				return mapAVStatus([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]);

			if ([key isEqualToString:@"location"])
				return locationStatus();

			if ([key isEqualToString:@"location_always"])
				return locationAlwaysStatus();

			if ([key isEqualToString:@"tracking"])
				return trackingStatus();

			// Videos live in the same photo library as images, so they share one system permission.
			if ([key isEqualToString:@"images"] || [key isEqualToString:@"video"])
				return imagesStatus();

			if ([key isEqualToString:@"bluetooth"])
				return bluetoothStatus();

			if ([key isEqualToString:@"contacts"])
				return mapEntityStatus((NSInteger)[CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts]);

			if ([key isEqualToString:@"calendar"])
				return calendarStatus();

			if ([key isEqualToString:@"motion"])
				return motionStatus();

			if ([key isEqualToString:@"biometrics"])
				return biometricsStatus();

			if ([key isEqualToString:@"audio"])
				return audioStatus();

			if ([key isEqualToString:@"notifications"])
				return notificationsStatus();

			// "storage" and "external_storage" have no iOS equivalent: apps always own their sandbox.
			return StatusGranted;
		}

		void requestPermission(const char* permission)
		{
			NSString* key = toNSString(permission);

			// iOS only ever prompts once, and never calls back when it won't prompt: don't leave a request pending.
			if (isPending(key) || checkPermission(permission) != StatusNotDetermined)
				return;

			if ([key isEqualToString:@"camera"] || [key isEqualToString:@"microphone"])
			{
				AVMediaType type = [key isEqualToString:@"camera"] ? AVMediaTypeVideo : AVMediaTypeAudio;

				setPending(key, YES);
				[AVCaptureDevice requestAccessForMediaType:type completionHandler:^(BOOL granted) { setPending(key, NO); }];
			}
			else if ([key isEqualToString:@"location"])
			{
				setPending(key, YES);

				// The manager must be created on, and kept alive by, the main thread.
				runOnMain(^{
					if (locationManager == nil)
					{
						locationDelegate = [[MTLocationDelegate alloc] init];
						locationManager = [[CLLocationManager alloc] init];
						locationManager.delegate = locationDelegate;
					}

					[locationManager requestWhenInUseAuthorization];
				});
			}
			else if ([key isEqualToString:@"location_always"])
			{
				setPending(key, YES);
				[[NSUserDefaults standardUserDefaults] setBool:YES forKey:kAskedAlwaysKey];

				runOnMain(^{
					if (locationManager == nil)
					{
						locationDelegate = [[MTLocationDelegate alloc] init];
						locationManager = [[CLLocationManager alloc] init];
						locationManager.delegate = locationDelegate;
					}

					// Keeping "while using" at the upgrade prompt doesn't call the delegate, so also finish when the app
					// becomes active again after the prompt took focus. If no prompt ever shows, give up after a while.
					__block BOOL promptShown = NO;
					__block id resignObserver = nil;
					__block id activeObserver = nil;
					NSNotificationCenter* center = [NSNotificationCenter defaultCenter];

					resignObserver = [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* note)
					{
						promptShown = YES;
						[center removeObserver:resignObserver];

						activeObserver = [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification* inner)
						{
							[center removeObserver:activeObserver];
							setPending(@"location_always", NO);
						}];
					}];

					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
						if (!promptShown)
						{
							[center removeObserver:resignObserver];
							setPending(@"location_always", NO);
						}
					});

					[locationManager requestAlwaysAuthorization];
				});
			}
			else if ([key isEqualToString:@"tracking"])
			{
				if (@available(iOS 14.0, *))
				{
					setPending(key, YES);
					[ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) { setPending(key, NO); }];
				}
			}
			else if ([key isEqualToString:@"bluetooth"])
			{
				setPending(key, YES);

				// Creating the manager is what makes iOS show the Bluetooth prompt.
				runOnMain(^{
					if (bluetoothManager == nil)
					{
						bluetoothDelegate = [[MTBluetoothDelegate alloc] init];
						bluetoothManager = [[CBCentralManager alloc] initWithDelegate:bluetoothDelegate queue:nil options:@{ CBCentralManagerOptionShowPowerAlertKey: @NO }];
					}
				});
			}
			else if ([key isEqualToString:@"contacts"])
			{
				setPending(key, YES);
				[[[CNContactStore alloc] init] requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError* error) { setPending(key, NO); }];
			}
			else if ([key isEqualToString:@"calendar"])
			{
				setPending(key, YES);

				EKEventStore* store = [[EKEventStore alloc] init];

				// The store must stay alive until the prompt is answered, which the block capturing it ensures.
				if (@available(iOS 17.0, *))
					[store requestFullAccessToEventsWithCompletion:^(BOOL granted, NSError* error) { (void)store; setPending(key, NO); }];
				else
					[store requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError* error) { (void)store; setPending(key, NO); }];
			}
			else if ([key isEqualToString:@"motion"])
			{
				setPending(key, YES);

				// There is no request call: asking for activity data is what triggers the prompt.
				CMMotionActivityManager* manager = [[CMMotionActivityManager alloc] init];
				[manager queryActivityStartingFromDate:[NSDate dateWithTimeIntervalSinceNow:-60]
												toDate:[NSDate date]
											   toQueue:[[NSOperationQueue alloc] init]
										   withHandler:^(NSArray<CMMotionActivity*>* activities, NSError* error) { (void)manager; setPending(key, NO); }];
			}
			else if ([key isEqualToString:@"images"] || [key isEqualToString:@"video"])
			{
				setPending(key, YES);

				if (@available(iOS 14.0, *))
					[PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) { setPending(key, NO); }];
				else
					[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) { setPending(key, NO); }];
			}
			else if ([key isEqualToString:@"audio"])
			{
				setPending(key, YES);
				[MPMediaLibrary requestAuthorization:^(MPMediaLibraryAuthorizationStatus status) { setPending(key, NO); }];
			}
			else if ([key isEqualToString:@"notifications"])
			{
				setPending(key, YES);

				UNAuthorizationOptions options = UNAuthorizationOptionAlert | UNAuthorizationOptionBadge | UNAuthorizationOptionSound;
				[[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError* error) { setPending(key, NO); }];
			}
		}

		bool isPermissionRequestPending(const char* permission)
		{
			return isPending(toNSString(permission));
		}

		void openSettings()
		{
			runOnMain(^{
				NSURL* url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];

				if (url != nil)
					[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
			});
		}
	}
}
