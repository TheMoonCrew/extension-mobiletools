package mobiletools;

/**
 * Runtime permissions that can be checked and requested through `Permissions`.
 *
 * The values are the identifiers shared with the native backends, so they must not change.
 *
 * Declaring the permission in your app is still required:
 * - Android: add the matching `<config:android permission="..." />` to your `project.xml`.
 * - iOS: add the matching `NS...UsageDescription` key to your Info.plist.
 *
 * See the README for the exact entries.
 */
enum abstract Permission(String) to String
{
	/** Camera access. */
	var CAMERA = 'camera';

	/** Microphone / audio recording. */
	var MICROPHONE = 'microphone';

	/** Location while the app is in use (Android: fine + coarse). */
	var LOCATION = 'location';

	/**
	 * Location while the app is in the background. Request `LOCATION` first: from Android 11 the system
	 * refuses background location until foreground location is granted, and then sends the user to a
	 * settings screen instead of showing a dialog. On iOS it upgrades "while using" to "always" (asked once).
	 */
	var LOCATION_ALWAYS = 'location_always';

	/**
	 * Permission to track the user across other companies' apps and websites (App Tracking Transparency).
	 * Needed before reading the advertising identifier. iOS 14+ only; always `GRANTED` elsewhere.
	 */
	var TRACKING = 'tracking';

	/** Reading the phone state, e.g. the network type or whether a call is active. Android only; always `GRANTED` on iOS. */
	var PHONE = 'phone';

	/**
	 * Discovering nearby Wi-Fi devices without needing location (Android 13+).
	 * Always `GRANTED` before that, and on iOS.
	 */
	var NEARBY_WIFI = 'nearby_wifi';

	/** Body sensors such as a heart rate monitor (Android). iOS keeps these behind HealthKit, so it reports `GRANTED`. */
	var BODY_SENSORS = 'body_sensors';

	/**
	 * Drawing over other apps (`SYSTEM_ALERT_WINDOW`). Granted on a settings screen, not a dialog. Android only.
	 */
	var OVERLAY = 'overlay';

	/**
	 * Running without battery optimizations, so the system doesn't pause the app in the background
	 * (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`). Asks with a system dialog. Android only, and restricted by Google Play.
	 */
	var IGNORE_BATTERY_OPTIMIZATIONS = 'ignore_battery_optimizations';

	/**
	 * Scheduling exact alarms (`SCHEDULE_EXACT_ALARM`). Granted on a settings screen from Android 12;
	 * always `GRANTED` before that and on iOS.
	 */
	var EXACT_ALARM = 'exact_alarm';

	/** Changing system settings such as the brightness (`WRITE_SETTINGS`). Granted on a settings screen. Android only. */
	var WRITE_SETTINGS = 'write_settings';

	/**
	 * Installing other apps, e.g. an in-app updater (`REQUEST_INSTALL_PACKAGES`). Granted on a settings screen
	 * from Android 8; always `GRANTED` before that and on iOS. Restricted by Google Play.
	 */
	var INSTALL_PACKAGES = 'install_packages';

	/** Posting notifications. */
	var NOTIFICATIONS = 'notifications';

	/** Read access to the user's images (iOS: the photo library). */
	var IMAGES = 'images';

	/** Read access to the user's audio files (iOS: the media / music library). */
	var AUDIO = 'audio';

	/** Read access to the user's videos (iOS: the photo library, same as `IMAGES`). */
	var VIDEO = 'video';

	/**
	 * Connecting to and scanning for Bluetooth devices, e.g. controllers.
	 * Needs a runtime prompt from Android 12 (API 31) and iOS 13; before that it is always `GRANTED`.
	 */
	var BLUETOOTH = 'bluetooth';

	/** Read access to the user's contacts. */
	var CONTACTS = 'contacts';

	/** Access to the user's calendar events. */
	var CALENDAR = 'calendar';

	/**
	 * Motion and activity data, e.g. step counting (Android: `ACTIVITY_RECOGNITION`, iOS: Motion & Fitness).
	 * Plain sensors such as the accelerometer or gyroscope need no permission on either platform.
	 */
	var MOTION = 'motion';

	/**
	 * Whether biometric authentication can be used. Unlike the others this is **not** a prompt:
	 * neither platform lets an app ask for it, so `request()` never shows anything.
	 *
	 * - `GRANTED`: biometrics are available and enrolled.
	 * - `DENIED`: the device supports it but nothing is enrolled (or it is temporarily locked out).
	 *   The user can fix this in the system settings.
	 * - `DENIED_PERMANENTLY`: iOS only, Face ID was refused for this app.
	 * - `RESTRICTED`: no biometric hardware, or the OS is too old.
	 *
	 * The iOS Face ID prompt appears the first time you actually authenticate, and needs `NSFaceIDUsageDescription`.
	 */
	var BIOMETRICS = 'biometrics';

	/**
	 * Classic storage read/write permission. Only needed up to Android 12L (API 32);
	 * from Android 13 and on iOS it is always `GRANTED`.
	 */
	var STORAGE = 'storage';

	/**
	 * Full access to shared external storage, outside your app's own folders.
	 *
	 * Up to Android 10 this is the regular storage prompt. From Android 11 it is the
	 * "All files access" switch, which opens a system settings screen instead of a dialog
	 * (and is restricted by Google Play). Always `GRANTED` on iOS.
	 */
	var EXTERNAL_STORAGE = 'external_storage';
}
