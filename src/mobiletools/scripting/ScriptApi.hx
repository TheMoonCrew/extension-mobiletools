package mobiletools.scripting;

import haxe.Json;
import mobiletools.Haptics;
import mobiletools.ImpactStyle;
import mobiletools.MobileTools;
import mobiletools.NotificationType;

/**
 * The variables every script starts with. This is the whole surface a script can touch,
 * so keep it small: scripts come from mods the user downloaded.
 */
class ScriptApi
{
	/** Builds a fresh set of default variables. */
	public static function defaults():Map<String, Dynamic>
	{
		var variables:Map<String, Dynamic> = new Map();

		variables.set('Std', Std);
		variables.set('Math', Math);
		variables.set('StringTools', StringTools);
		variables.set('Json', createJsonApi());
		variables.set('mobile', createMobileApi());

		return variables;
	}

	/**
	 * `Json.parse()` and `Json.stringify()` as plain functions: on some targets `haxe.Json`'s own functions
	 * are inlined and so cannot be called through reflection, which is how scripts call everything.
	 */
	private static function createJsonApi():Dynamic
	{
		return {
			parse: function(text:String):Dynamic return Json.parse(text),
			stringify: function(value:Dynamic):String return Json.stringify(value),
			prettyStringify: function(value:Dynamic):String return Json.stringify(value, null, '  ')
		};
	}

	/**
	 * `mobile.*` for scripts: a small facade over `MobileTools` and `Haptics`.
	 * Styles are plain strings because scripts cannot use Haxe enum abstracts.
	 *
	 * Every function takes all of its arguments, since optional parameters are not portable through reflection.
	 */
	private static function createMobileApi():Dynamic
	{
		return {
			isMobile: MobileTools.isMobile,
			isSupported: MobileTools.isSupported,
			showToast: function(message:String):Void MobileTools.showToast(message),
			showLongToast: function(message:String):Void MobileTools.showToast(message, LONG),
			vibrate: function(milliseconds:Int):Void MobileTools.vibrate(milliseconds),
			selection: function():Void Haptics.selection(),
			impact: function(style:String):Void Haptics.impact(parseImpact(style)),
			notification: function(type:String):Void Haptics.notification(parseNotification(type)),
			getDeviceInfo: function():Dynamic return MobileTools.getDeviceInfo()
		};
	}

	private static function parseImpact(style:String):ImpactStyle
	{
		return switch (style)
		{
			case 'light': LIGHT;
			case 'medium': MEDIUM;
			case 'heavy': HEAVY;
			case 'soft': SOFT;
			case 'rigid': RIGID;
			default: throw 'Unknown impact style "$style", expected light, medium, heavy, soft or rigid';
		}
	}

	private static function parseNotification(type:String):NotificationType
	{
		return switch (type)
		{
			case 'success': SUCCESS;
			case 'warning': WARNING;
			case 'error': ERROR;
			default: throw 'Unknown notification type "$type", expected success, warning or error';
		}
	}
}
