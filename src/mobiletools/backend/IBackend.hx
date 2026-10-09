package mobiletools.backend;

import mobiletools.DeviceInfo;
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
}
