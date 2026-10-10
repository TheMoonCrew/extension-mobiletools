package mobiletools;

import mobiletools.DeviceInfo;
import mobiletools.StorageDirectory;
import mobiletools.ToastDuration;
import mobiletools.backend.AndroidBackend;
import mobiletools.backend.IBackend;
import mobiletools.backend.IOSBackend;
import mobiletools.backend.NullBackend;

/**
 * Cross-platform entry point of `extension-mobiletools`.
 *
 * All methods are safe to call on any target. Where no native backend exists
 * (desktop, html5) they do nothing, so no `#if` guards are needed. Runtime
 * permissions live in `Permissions`.
 *
 * ```haxe
 * MobileTools.showToast('Level saved!');
 * MobileTools.vibrate(50);
 * trace(MobileTools.getDeviceInfo().model);
 * ```
 */
class MobileTools
{
	/** Backend selected at compile time for the current target. */
	@:allow(mobiletools.Permissions, mobiletools.Haptics)
	private static var backend:IBackend = createBackend();

	/** `true` when running on a mobile target (Android or iOS). */
	public static var isMobile(get, never):Bool;

	/** `true` when a native backend is active, i.e. calls actually reach the OS. */
	public static var isSupported(get, never):Bool;

	/**
	 * Shows a short message on screen without blocking the app.
	 *
	 * @param message  Text to display.
	 * @param duration `SHORT` (default) or `LONG`.
	 */
	public static function showToast(message:String, duration:ToastDuration = SHORT):Void
	{
		if (message == null || message.length == 0)
			return;

		backend.showToast(message, duration);
	}

	/**
	 * Vibrates the device.
	 *
	 * @param milliseconds How long to vibrate. Values <= 0 are ignored.
	 */
	public static function vibrate(milliseconds:Int = 100):Void
	{
		if (milliseconds <= 0)
			return;

		backend.vibrate(milliseconds);
	}

	/** Stops any vibration started with `vibrate()`. */
	public static function cancelVibration():Void
	{
		backend.cancelVibration();
	}

	/**
	 * Prevents (or allows again) the screen from turning off while the app is in the foreground.
	 */
	public static function setKeepScreenOn(enabled:Bool):Void
	{
		backend.setKeepScreenOn(enabled);
	}

	/** Returns basic device information, or placeholder values when unsupported. */
	public static function getDeviceInfo():DeviceInfo
	{
		return backend.getDeviceInfo();
	}

	/**
	 * Replaces the backend that talks to the platform. For tests, or to support a platform this library doesn't.
	 * Call it before anything else uses `MobileTools`.
	 */
	public static function setBackend(newBackend:IBackend):Void
	{
		backend = newBackend;
	}

	/**
	 * Returns the absolute path of a well-known folder, without a trailing slash.
	 *
	 * On desktop every folder is the working directory. Returns an empty string when the
	 * folder is unavailable (e.g. no external storage mounted, or html5).
	 */
	public static function getDirectory(directory:StorageDirectory):String
	{
		return backend.getDirectory(directory);
	}

	private static function createBackend():IBackend
	{
		#if (lime && android)
		return new AndroidBackend();
		#elseif (cpp && ios)
		return new IOSBackend();
		#else
		return new NullBackend();
		#end
	}

	@:noCompletion private static inline function get_isMobile():Bool
	{
		#if (android || ios)
		return true;
		#else
		return false;
		#end
	}

	@:noCompletion private static function get_isSupported():Bool
	{
		return backend.isNative;
	}
}
