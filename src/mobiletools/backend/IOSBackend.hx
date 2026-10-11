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

	public function setFullscreen(enabled:Bool):Void
	{
		IOSNative.setFullscreen(enabled);
	}

	public function getSafeArea():SafeArea
	{
		return SafeAreaTools.parse(IOSNative.getSafeArea().toString());
	}

	public function getDirectory(directory:StorageDirectory):String
	{
		return IOSNative.getDirectory((directory : Int)).toString();
	}

	public function impact(style:ImpactStyle):Void
	{
		IOSNative.impact((style : Int));
	}

	public function notification(type:NotificationType):Void
	{
		IOSNative.notification((type : Int));
	}

	public function selection():Void
	{
		IOSNative.selection();
	}

	public function playHapticPattern(pattern:HapticPattern):Void
	{
		IOSNative.playHapticPattern(ConstCharStar.fromString(pattern.toCompact()));
	}

	public function cancelHaptics():Void
	{
		IOSNative.cancelHaptics();
	}

	public function getHapticCapabilities():HapticCapabilities
	{
		return HapticCapabilitiesTools.fromBits(IOSNative.getHapticCapabilities());
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

	public function pickFile(extensions:String):Bool
	{
		return IOSNative.pickFile(ConstCharStar.fromString(extensions));
	}

	public function isFilePickerPending():Bool
	{
		return IOSNative.isFilePickerPending();
	}

	public function getPickedFile():String
	{
		return IOSNative.getPickedFile().toString();
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
