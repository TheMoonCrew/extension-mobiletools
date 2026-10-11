package mobiletools.backend;

import mobiletools.DeviceInfo;
import mobiletools.HapticCapabilities;
import mobiletools.HapticPattern;
import mobiletools.ImpactStyle;
import mobiletools.NotificationType;
import mobiletools.Permission;
import mobiletools.PermissionStatus;
import mobiletools.SafeArea;
import mobiletools.StorageDirectory;
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

	public function setFullscreen(enabled:Bool):Void {}

	public function getSafeArea():SafeArea
	{
		return SafeAreaTools.none();
	}

	public function getDirectory(directory:StorageDirectory):String
	{
		#if sys
		// No sandbox on desktop: everything lives next to the working directory, which keeps mods easy to try.
		return haxe.io.Path.removeTrailingSlashes(Sys.getCwd());
		#else
		return '';
		#end
	}

	public function impact(style:ImpactStyle):Void {}

	public function notification(type:NotificationType):Void {}

	public function selection():Void {}

	public function playHapticPattern(pattern:HapticPattern):Void {}

	public function cancelHaptics():Void {}

	public function getHapticCapabilities():HapticCapabilities
	{
		return HapticCapabilitiesTools.none();
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

	public function pickFile(extensions:String):Bool
	{
		return false;
	}

	public function isFilePickerPending():Bool
	{
		return false;
	}

	public function getPickedFile():String
	{
		return '';
	}

	@:noCompletion private inline function get_isNative():Bool
	{
		return false;
	}
}
