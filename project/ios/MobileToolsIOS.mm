#include "MobileToolsIOS.h"

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreLocation/CoreLocation.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>

#include <cstdlib>
#include <string>
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
}

@end

static CLLocationManager* locationManager;
static MTLocationDelegate* locationDelegate;

#pragma mark - Camera / microphone / photos / notifications

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

static int photosStatus()
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

			if ([key isEqualToString:@"photos"])
				return photosStatus();

			if ([key isEqualToString:@"notifications"])
				return notificationsStatus();

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
			else if ([key isEqualToString:@"photos"])
			{
				setPending(key, YES);

				if (@available(iOS 14.0, *))
					[PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) { setPending(key, NO); }];
				else
					[PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) { setPending(key, NO); }];
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
