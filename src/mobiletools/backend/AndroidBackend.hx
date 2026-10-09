package mobiletools.backend;

import mobiletools.DeviceInfo;
import mobiletools.Permission;
import mobiletools.PermissionStatus;
import mobiletools.ToastDuration;

#if (lime && android)
import haxe.Json;
import lime.system.JNI;
#end

/**
 * Android backend. Calls into `com.mobiletools.MobileTools` (see `java/`) through Lime's JNI bridge.
 */
#if (lime && android)
class AndroidBackend implements IBackend
{
	private static inline var JAVA_CLASS:String = 'com/mobiletools/MobileTools';

	private static var showToastJNI:Dynamic;
	private static var vibrateJNI:Dynamic;
	private static var cancelVibrationJNI:Dynamic;
	private static var setKeepScreenOnJNI:Dynamic;
	private static var getDeviceInfoJNI:Dynamic;
	private static var checkPermissionJNI:Dynamic;
	private static var requestPermissionJNI:Dynamic;
	private static var isPermissionRequestPendingJNI:Dynamic;
	private static var openSettingsJNI:Dynamic;

	public var isNative(get, never):Bool;

	public function new() {}

	public function showToast(message:String, duration:ToastDuration):Void
	{
		if (showToastJNI == null)
			showToastJNI = JNI.createStaticMethod(JAVA_CLASS, 'showToast', '(Ljava/lang/String;I)V');

		showToastJNI(message, (duration : Int));
	}

	public function vibrate(milliseconds:Int):Void
	{
		if (vibrateJNI == null)
			vibrateJNI = JNI.createStaticMethod(JAVA_CLASS, 'vibrate', '(I)V');

		vibrateJNI(milliseconds);
	}

	public function cancelVibration():Void
	{
		if (cancelVibrationJNI == null)
			cancelVibrationJNI = JNI.createStaticMethod(JAVA_CLASS, 'cancelVibration', '()V');

		cancelVibrationJNI();
	}

	public function setKeepScreenOn(enabled:Bool):Void
	{
		if (setKeepScreenOnJNI == null)
			setKeepScreenOnJNI = JNI.createStaticMethod(JAVA_CLASS, 'setKeepScreenOn', '(Z)V');

		setKeepScreenOnJNI(enabled);
	}

	public function getDeviceInfo():DeviceInfo
	{
		if (getDeviceInfoJNI == null)
			getDeviceInfoJNI = JNI.createStaticMethod(JAVA_CLASS, 'getDeviceInfo', '()Ljava/lang/String;');

		try
		{
			return Json.parse(getDeviceInfoJNI());
		}
		catch (e:Dynamic)
		{
			return DeviceInfoTools.unknown();
		}
	}

	public function checkPermission(permission:Permission):PermissionStatus
	{
		if (checkPermissionJNI == null)
			checkPermissionJNI = JNI.createStaticMethod(JAVA_CLASS, 'checkPermission', '(Ljava/lang/String;)I');

		return (checkPermissionJNI((permission : String)) : Int);
	}

	public function requestPermission(permission:Permission):Void
	{
		if (requestPermissionJNI == null)
			requestPermissionJNI = JNI.createStaticMethod(JAVA_CLASS, 'requestPermission', '(Ljava/lang/String;)V');

		requestPermissionJNI((permission : String));
	}

	public function isPermissionRequestPending(permission:Permission):Bool
	{
		if (isPermissionRequestPendingJNI == null)
			isPermissionRequestPendingJNI = JNI.createStaticMethod(JAVA_CLASS, 'isPermissionRequestPending', '(Ljava/lang/String;)Z');

		return isPermissionRequestPendingJNI((permission : String));
	}

	public function openSettings():Void
	{
		if (openSettingsJNI == null)
			openSettingsJNI = JNI.createStaticMethod(JAVA_CLASS, 'openSettings', '()V');

		openSettingsJNI();
	}

	@:noCompletion private inline function get_isNative():Bool
	{
		return true;
	}
}
#else
// Keeps the class resolvable on non-Android targets; it is never instantiated there.
class AndroidBackend extends NullBackend {}
#end
