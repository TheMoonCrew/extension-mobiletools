package mobiletools.backend;

import mobiletools.DeviceInfo;
import mobiletools.HapticCapabilities;
import mobiletools.HapticPattern;
import mobiletools.ImpactStyle;
import mobiletools.NotificationType;
import mobiletools.Permission;
import mobiletools.PermissionStatus;
import mobiletools.StorageDirectory;
import mobiletools.ToastDuration;

/**
 * Contract implemented by every platform backend.
 *
 * `MobileTools` picks exactly one backend at startup, so adding support
 * for a new platform only requires a new class implementing this interface.
 */
interface IBackend
{
	/** `true` if this backend talks to real native code. */
	public var isNative(get, never):Bool;

	public function showToast(message:String, duration:ToastDuration):Void;
	public function vibrate(milliseconds:Int):Void;
	public function cancelVibration():Void;
	public function setKeepScreenOn(enabled:Bool):Void;
	public function getDeviceInfo():DeviceInfo;

	/** Absolute path of the folder, without a trailing slash, or an empty string when unavailable. */
	public function getDirectory(directory:StorageDirectory):String;

	public function impact(style:ImpactStyle):Void;
	public function notification(type:NotificationType):Void;
	public function selection():Void;

	/** Plays the pattern, replacing any pattern still playing. The pattern is already scaled by `Haptics.intensity`. */
	public function playHapticPattern(pattern:HapticPattern):Void;

	/** Stops a pattern started with `playHapticPattern()`. */
	public function cancelHaptics():Void;

	public function getHapticCapabilities():HapticCapabilities;

	/** Current status, without prompting. Must be cheap and synchronous. */
	public function checkPermission(permission:Permission):PermissionStatus;

	/**
	 * Starts the system prompt. Must return immediately, and must make
	 * `isPermissionRequestPending()` return `true` before returning if a prompt was shown.
	 */
	public function requestPermission(permission:Permission):Void;

	/** `true` from `requestPermission()` until the user answered the prompt. */
	public function isPermissionRequestPending(permission:Permission):Bool;

	/** Opens the app's page in the system settings. */
	public function openSettings():Void;
}
