package mobiletools.backend;

import mobiletools.DeviceInfo;
import mobiletools.ToastDuration;

/**
 * Fallback backend used on targets without native support (desktop, html5, iOS for now).
 *
 * Every call is a harmless no-op so game/app code never needs `#if` guards.
 */
class NullBackend implements IBackend
{
	public var isNative(get, never):Bool;

	public function new() {}

	public function showToast(message:String, duration:ToastDuration):Void {}

	public function vibrate(milliseconds:Int):Void {}

	public function cancelVibration():Void {}

	public function setKeepScreenOn(enabled:Bool):Void {}

	public function getDeviceInfo():DeviceInfo
	{
		return DeviceInfoTools.unknown();
	}

	@:noCompletion private inline function get_isNative():Bool
	{
		return false;
	}
}
