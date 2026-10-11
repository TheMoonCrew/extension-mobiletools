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

	/** Hides or shows the system bars, see `MobileTools.setFullscreen()`. Must keep applying it until changed again. */
	public function setFullscreen(enabled:Bool):Void;

	/** Insets in pixels, see `MobileTools.getSafeArea()`. */
	public function getSafeArea():SafeArea;

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

	/**
	 * Shows the system file picker. `extensions` is a comma separated list without dots, empty for any file.
	 * Must return immediately, `false` if no picker could be shown, and make `isFilePickerPending()` return `true`
	 * before returning `true`.
	 */
	public function pickFile(extensions:String):Bool;

	/** `true` from `pickFile()` until the user chose a file (and it was copied) or cancelled. */
	public function isFilePickerPending():Bool;

	/** Absolute path of a private copy of the file chosen last, or an empty string if the user cancelled. */
	public function getPickedFile():String;
}
