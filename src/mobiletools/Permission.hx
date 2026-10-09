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

	/** Read access to the user's photo library. */
	var PHOTOS = 'photos';
}
