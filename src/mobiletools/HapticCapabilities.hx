package mobiletools;

/**
 * What the device's haptic hardware can do, from `Haptics.capabilities`.
 *
 * Patterns always play, but they are approximated on weaker hardware: without amplitude control
 * every vibration is simply on or off, and without sharpness control it is ignored.
 */
typedef HapticCapabilities =
{
	/** The device can vibrate at all. */
	var supported:Bool;

	/** The strength of a vibration can be varied (Android 8+ with a suitable motor, iOS with Core Haptics). */
	var amplitudeControl:Bool;

	/** The sharpness of a vibration can be varied (iOS with Core Haptics). */
	var sharpnessControl:Bool;
}

class HapticCapabilitiesTools
{
	/** Nothing is available. */
	public static function none():HapticCapabilities
	{
		return {supported: false, amplitudeControl: false, sharpnessControl: false};
	}

	/** Reads the bit field the native backends return: 1 supported, 2 amplitude control, 4 sharpness control. */
	public static function fromBits(bits:Int):HapticCapabilities
	{
		return {supported: (bits & 1) != 0, amplitudeControl: (bits & 2) != 0, sharpnessControl: (bits & 4) != 0};
	}
}
