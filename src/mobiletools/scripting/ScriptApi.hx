package mobiletools.scripting;

import haxe.Json;
import mobiletools.HapticLibrary;
import mobiletools.HapticPattern;
import mobiletools.Haptics;
import mobiletools.ImpactStyle;
import mobiletools.MobileTools;
import mobiletools.NotificationType;
import mobiletools.mods.ModInfo.ModInfoTools;

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
		variables.set('haptics', createHapticsApi());

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
	 * Scripts can read whether the app is fullscreen and where the safe area is, but only the app can change it.
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
			getDeviceInfo: function():Dynamic return MobileTools.getDeviceInfo(),
			platform: ModInfoTools.currentPlatform(),
			isFullscreen: function():Bool return MobileTools.isFullscreen,
			getSafeArea: function():Dynamic return MobileTools.getSafeArea()
		};
	}

	/**
	 * `haptics.*` for scripts: custom patterns, the built in presets and anything mods provide.
	 *
	 * ```
	 * haptics.play("heartbeat");                                   // by name, returns false if unknown
	 * haptics.pattern().tap(0, 1, 0.9).hold(100, 300, 0.5).play(); // build and play
	 * haptics.define("my-hit", haptics.pattern().tap(0).tap(80, 0.6)); // keep it for later
	 * haptics.impact("heavy");  haptics.notification("success");  haptics.selection();
	 * haptics.stop();
	 * ```
	 *
	 * Builder methods take their trailing arguments as optional: `tap(time, [intensity], [sharpness])`,
	 * `hold(time, duration, [intensity], [sharpness])`, `ramp(time, duration, from, to, [steps], [sharpness])`,
	 * `repeat(count, interval)`. They return the builder so calls chain.
	 *
	 * Scripts can't change `Haptics.enabled` or `Haptics.intensity`: those belong to the user.
	 *
	 * @param onDefine Called when a script saves a pattern with `define()`. Without it, patterns go to a shared "scripts" layer.
	 */
	public static function createHapticsApi(?onDefine:(name:String, pattern:HapticPattern) -> Void):Dynamic
	{
		if (onDefine == null)
			onDefine = function(name, pattern) HapticLibrary.define('scripts', HapticLibrary.PRIORITY_APP, name, pattern);

		var api:Dynamic = {
			selection: function():Void Haptics.selection(),
			impact: function(style:String):Void Haptics.impact(parseImpact(style)),
			notification: function(type:String):Void Haptics.notification(parseNotification(type)),
			play: function(name:String):Bool return Haptics.playNamed(name),
			stop: function():Void Haptics.stop(),
			has: function(name:String):Bool return Haptics.has(name),
			names: function():Array<String> return Haptics.patternNames(),
			isEnabled: function():Bool return Haptics.enabled,
			capabilities: function():Dynamic return Haptics.capabilities,
			pattern: Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic return createPatternBuilder(new HapticPattern(args.length > 0 ? args[0] : null))),
			fromJson: function(json:String):Dynamic return createPatternBuilder(HapticPattern.fromJson(json)),
			fromData: function(data:Dynamic):Dynamic return createPatternBuilder(HapticPattern.fromData(data)),
			define: function(name:String, builder:Dynamic):Void onDefine(name, unwrapPattern(builder))
		};

		return api;
	}

	/** The object scripts chain on: it wraps a `HapticPattern` and exposes only safe, validated operations. */
	private static function createPatternBuilder(pattern:HapticPattern):Dynamic
	{
		var builder:Dynamic = {};

		function method(name:String, body:Array<Dynamic>->Void):Void
		{
			Reflect.setField(builder, name, Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic
			{
				body(args);
				return builder;
			}));
		}

		method('tap', function(a) pattern.tap(number(a, 0), number(a, 1, 1), number(a, 2, 0.5)));
		method('hold', function(a) pattern.hold(number(a, 0), number(a, 1), number(a, 2, 1), number(a, 3, 0.5)));
		method('ramp', function(a) pattern.ramp(number(a, 0), number(a, 1), number(a, 2), number(a, 3), Std.int(number(a, 4, 8)), number(a, 5, 0.5)));
		method('repeat', function(a) pattern.repeat(Std.int(number(a, 0)), number(a, 1)));

		Reflect.setField(builder, 'play', function():Void Haptics.play(pattern));
		Reflect.setField(builder, 'duration', function():Float return pattern.duration);
		Reflect.setField(builder, 'toJson', function():String return pattern.toJson());
		Reflect.setField(builder, 'getPattern', function():HapticPattern return pattern);

		return builder;
	}

	/** The `HapticPattern` behind a builder, refusing anything a script made up. */
	private static function unwrapPattern(builder:Dynamic):HapticPattern
	{
		var getter:Dynamic = builder != null ? Reflect.field(builder, 'getPattern') : null;
		var pattern:Dynamic = Reflect.isFunction(getter) ? getter() : null;

		if (!Std.isOfType(pattern, HapticPattern))
			throw 'Expected a pattern made with haptics.pattern()';

		return pattern;
	}

	private static function number(args:Array<Dynamic>, index:Int, ?fallback:Float):Float
	{
		var value:Dynamic = index < args.length ? args[index] : null;

		if (value == null)
		{
			if (fallback == null)
				throw 'Missing argument ${index + 1}';

			return fallback;
		}

		if (!Std.isOfType(value, Float))
			throw 'Argument ${index + 1} must be a number';

		return value;
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
