package mobiletools.backend;

import mobiletools.DeviceInfo;
import mobiletools.Permission;
import mobiletools.PermissionStatus;
import mobiletools.ToastDuration;

/**
 * Fallback backend used on targets without native support (desktop, html5).
 *
 * Every call is a harmless no-op so game/app code never needs `#if` guards.
 * Permissions are reported as `GRANTED`, since these targets have no runtime permission prompt.
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

	public function checkPermission(permission:Permission):PermissionStatus
	{
		return GRANTED;
	}

	public function requestPermission(permission:Permission):Void {}

	public function isPermissionRequestPending(permission:Permission):Bool
	{
		return false;
	}

	public function openSettings():Void {}

	@:noCompletion private inline function get_isNative():Bool
	{
		return false;
	}
}
