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

	/** Posting notifications. */
	var NOTIFICATIONS = 'notifications';

	/** Read access to the user's images (iOS: the photo library). */
	var IMAGES = 'images';

	/** Read access to the user's audio files (iOS: the media / music library). */
	var AUDIO = 'audio';

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
