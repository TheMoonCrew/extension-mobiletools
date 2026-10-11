package mobiletools;

/**
 * Space, in pixels, that the system covers or cuts out on each edge of the screen: the status bar,
 * navigation bar or home indicator when visible, notches and punch-hole cameras, and on iOS the rounded corners.
 *
 * Keep buttons and text inside it, especially in fullscreen, where the game draws behind all of these.
 * Returned by `MobileTools.getSafeArea()`.
 */
typedef SafeArea =
{
	var top:Int;
	var right:Int;
	var bottom:Int;
	var left:Int;
}

class SafeAreaTools
{
	/** No insets at all, what targets without a native backend report. */
	public static function none():SafeArea
	{
		return {
			top: 0,
			right: 0,
			bottom: 0,
			left: 0
		};
	}

	/** Parses the "top,right,bottom,left" string the native backends return. Anything malformed gives `none()`. */
	public static function parse(text:String):SafeArea
	{
		var parts = text != null ? text.split(',') : [];

		if (parts.length != 4)
			return none();

		var values = [for (part in parts) Std.parseInt(part)];

		for (value in values)
		{
			if (value == null || value < 0)
				return none();
		}

		return {
			top: values[0],
			right: values[1],
			bottom: values[2],
			left: values[3]
		};
	}
}
