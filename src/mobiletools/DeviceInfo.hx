package mobiletools;

/**
 * Basic information about the device the application is running on.
 *
 * On targets without a native backend every field holds a safe default
 * (see `DeviceInfo.unknown()`).
 */
typedef DeviceInfo =
{
	/** Hardware manufacturer, e.g. `"Google"`. */
	var manufacturer:String;

	/** Device model, e.g. `"Pixel 7"`. */
	var model:String;

	/** Human readable OS version, e.g. `"14"`. */
	var osVersion:String;

	/** Numeric OS API level (Android SDK_INT). `0` when unknown. */
	var apiLevel:Int;
}

class DeviceInfoTools
{
	/** Returns a `DeviceInfo` filled with placeholder values. */
	public static function unknown():DeviceInfo
	{
		return {
			manufacturer: 'unknown',
			model: 'unknown',
			osVersion: 'unknown',
			apiLevel: 0
		};
	}
}
