package mobiletools.backend;

import mobiletools.DeviceInfo;
import mobiletools.Permission;
import mobiletools.PermissionStatus;
import mobiletools.ToastDuration;

#if (cpp && ios)
import cpp.ConstCharStar;
import haxe.Json;
import mobiletools.backend.IOSNative;
#end

/**
 * iOS backend, backed by Objective-C++ (`project/ios/MobileToolsIOS.mm`).
 *
 * Platform differences:
 * - `vibrate()` ignores the duration: iOS only offers a fixed-length system vibration.
 * - `cancelVibration()` does nothing, a started vibration cannot be stopped.
 * - Toasts are drawn as an overlay on the key window, since iOS has no native toast.
 */
#if (cpp && ios)
class IOSBackend implements IBackend
{
	public var isNative(get, never):Bool;

	public function new() {}

	public function showToast(message:String, duration:ToastDuration):Void
	{
		IOSNative.showToast(ConstCharStar.fromString(message), (duration : Int));
	}

	public function vibrate(milliseconds:Int):Void
	{
		IOSNative.vibrate();
	}

	public function cancelVibration():Void {}

	public function setKeepScreenOn(enabled:Bool):Void
	{
		IOSNative.setKeepScreenOn(enabled);
	}

	public function getDeviceInfo():DeviceInfo
	{
		try
		{
			return Json.parse(IOSNative.getDeviceInfo().toString());
		}
		catch (e:Dynamic)
		{
			return DeviceInfoTools.unknown();
		}
	}

	public function checkPermission(permission:Permission):PermissionStatus
	{
		return IOSNative.checkPermission(ConstCharStar.fromString(permission));
	}

	public function requestPermission(permission:Permission):Void
	{
		IOSNative.requestPermission(ConstCharStar.fromString(permission));
	}

	public function isPermissionRequestPending(permission:Permission):Bool
	{
		return IOSNative.isPermissionRequestPending(ConstCharStar.fromString(permission));
	}

	public function openSettings():Void
	{
		IOSNative.openSettings();
	}

	@:noCompletion private inline function get_isNative():Bool
	{
		return true;
	}
}
#else
// Keeps the class resolvable on non-iOS targets; it is never instantiated there.
class IOSBackend extends NullBackend {}
#end
