package mobiletools;

/**
 * Result of `Permissions.check()` / `Permissions.request()`.
 *
 * The values are shared with the native backends, so they must not change.
 */
enum abstract PermissionStatus(Int) from Int to Int
{
	/** The user has not been asked yet; `Permissions.request()` will show the system prompt. */
	var NOT_DETERMINED = 0;

	/** The permission is granted (or the platform has no runtime permission for it). */
	var GRANTED = 1;

	/** Denied, but the system will still show the prompt again (Android only). */
	var DENIED = 2;

	/**
	 * Denied and the system will not prompt again. The only way forward is
	 * `Permissions.openSettings()`. On iOS every denial ends up here.
	 */
	var DENIED_PERMANENTLY = 3;

	/** Blocked by the system, e.g. parental controls (iOS). The user cannot change it. */
	var RESTRICTED = 4;

	/** `true` when the permission is granted. */
	public inline function isGranted():Bool
	{
		return this == 1;
	}

	/** `true` when `Permissions.request()` can still show a system prompt. */
	public inline function canRequest():Bool
	{
		return this == 0 || this == 2;
	}
}
