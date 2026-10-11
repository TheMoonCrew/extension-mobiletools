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
	private static var setFullscreenJNI:Dynamic;
	private static var getSafeAreaJNI:Dynamic;
	private static var getDirectoryJNI:Dynamic;
	private static var impactJNI:Dynamic;
	private static var notificationJNI:Dynamic;
	private static var selectionJNI:Dynamic;
	private static var playWaveformJNI:Dynamic;
	private static var cancelHapticsJNI:Dynamic;
	private static var getHapticCapabilitiesJNI:Dynamic;
	private static var checkPermissionJNI:Dynamic;
	private static var requestPermissionJNI:Dynamic;
	private static var isPermissionRequestPendingJNI:Dynamic;
	private static var openSettingsJNI:Dynamic;
	private static var pickFileJNI:Dynamic;
	private static var isFilePickerPendingJNI:Dynamic;
	private static var getPickedFileJNI:Dynamic;

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

	public function setFullscreen(enabled:Bool):Void
	{
		if (setFullscreenJNI == null)
			setFullscreenJNI = JNI.createStaticMethod(JAVA_CLASS, 'setFullscreen', '(Z)V');

		setFullscreenJNI(enabled);
	}

	public function getSafeArea():SafeArea
	{
		if (getSafeAreaJNI == null)
			getSafeAreaJNI = JNI.createStaticMethod(JAVA_CLASS, 'getSafeArea', '()Ljava/lang/String;');

		return SafeAreaTools.parse(getSafeAreaJNI());
	}

	public function getDirectory(directory:StorageDirectory):String
	{
		if (getDirectoryJNI == null)
			getDirectoryJNI = JNI.createStaticMethod(JAVA_CLASS, 'getDirectory', '(I)Ljava/lang/String;');

		var path:String = getDirectoryJNI((directory : Int));
		return path != null ? path : '';
	}

	public function impact(style:ImpactStyle):Void
	{
		if (impactJNI == null)
			impactJNI = JNI.createStaticMethod(JAVA_CLASS, 'impact', '(I)V');

		impactJNI((style : Int));
	}

	public function notification(type:NotificationType):Void
	{
		if (notificationJNI == null)
			notificationJNI = JNI.createStaticMethod(JAVA_CLASS, 'notification', '(I)V');

		notificationJNI((type : Int));
	}

	public function selection():Void
	{
		if (selectionJNI == null)
			selectionJNI = JNI.createStaticMethod(JAVA_CLASS, 'selection', '()V');

		selectionJNI();
	}

	public function playHapticPattern(pattern:HapticPattern):Void
	{
		var waveform = pattern.toWaveformString();

		if (waveform == '')
			return;

		if (playWaveformJNI == null)
			playWaveformJNI = JNI.createStaticMethod(JAVA_CLASS, 'playWaveform', '(Ljava/lang/String;)V');

		playWaveformJNI(waveform);
	}

	public function cancelHaptics():Void
	{
		if (cancelHapticsJNI == null)
			cancelHapticsJNI = JNI.createStaticMethod(JAVA_CLASS, 'cancelHaptics', '()V');

		cancelHapticsJNI();
	}

	public function getHapticCapabilities():HapticCapabilities
	{
		if (getHapticCapabilitiesJNI == null)
			getHapticCapabilitiesJNI = JNI.createStaticMethod(JAVA_CLASS, 'getHapticCapabilities', '()I');

		return HapticCapabilitiesTools.fromBits(getHapticCapabilitiesJNI());
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

	public function pickFile(extensions:String):Bool
	{
		if (pickFileJNI == null)
			pickFileJNI = JNI.createStaticMethod(JAVA_CLASS, 'pickFile', '(Ljava/lang/String;)Z');

		return pickFileJNI(extensions);
	}

	public function isFilePickerPending():Bool
	{
		if (isFilePickerPendingJNI == null)
			isFilePickerPendingJNI = JNI.createStaticMethod(JAVA_CLASS, 'isFilePickerPending', '()Z');

		return isFilePickerPendingJNI();
	}

	public function getPickedFile():String
	{
		if (getPickedFileJNI == null)
			getPickedFileJNI = JNI.createStaticMethod(JAVA_CLASS, 'getPickedFile', '()Ljava/lang/String;');

		var path:String = getPickedFileJNI();
		return path != null ? path : '';
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
