package mobiletools;

/**
 * Well-known folders returned by `MobileTools.getDirectory()`.
 *
 * The values are shared with the native backends, so they must not change.
 */
enum abstract StorageDirectory(Int) to Int
{
	/** Private to the app, always writable, never visible to the user. Removed on uninstall. */
	var INTERNAL = 0;

	/**
	 * The app's own folder on shared storage, writable without any permission.
	 * - Android: `Android/data/<package>/files`, reachable by file managers up to Android 10.
	 * - iOS: the Documents folder (shown in the Files app when `UIFileSharingEnabled` is set).
	 */
	var APP_EXTERNAL = 1;

	/**
	 * Root of the shared storage the user sees, e.g. `/storage/emulated/0`.
	 * Writing here needs `Permission.EXTERNAL_STORAGE`. iOS has no such folder and returns the Documents folder.
	 */
	var SHARED = 2;
}
