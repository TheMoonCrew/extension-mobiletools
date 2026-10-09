package mobiletools.backend;

import mobiletools.DeviceInfo;
import mobiletools.Permission;
import mobiletools.PermissionStatus;
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
