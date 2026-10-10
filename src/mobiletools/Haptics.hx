package mobiletools;

import mobiletools.HapticCapabilities;
import mobiletools.HapticPattern;
import mobiletools.ImpactStyle;
import mobiletools.NotificationType;

/**
 * Haptic feedback, from one-line UI taps to fully custom patterns.
 *
 * ```haxe
 * Haptics.selection();               // a picker or switch changed
 * Haptics.impact(MEDIUM);            // a button press, a collision
 * Haptics.notification(SUCCESS);     // a task finished
 *
 * Haptics.playNamed('heartbeat');    // a built in or mod provided pattern
 *
 * Haptics.play(new HapticPattern()   // your own
 *     .tap(0, 1, 0.9)
 *     .hold(100, 300, 0.5)
 *     .ramp(400, 400, 0.5, 0));
 * ```
 *
 * The semantic calls (`impact`, `notification`, `selection`) use the platform's own effects, so they feel
 * native. Patterns give you full control and are approximated on weaker hardware, see `capabilities`.
 * Everything is a no-op on targets without haptics.
 */
class Haptics
{
	/**
	 * Master switch. Set it to `false` from your settings screen (some people find vibration unpleasant,
	 * or it hurts battery life) and every haptic call, including from mods, stays silent.
	 */
	public static var enabled:Bool = true;

	/**
	 * Strength of custom patterns, 0 to 1. Applies to `play()` and `playNamed()`; the semantic effects
	 * (`impact()` and friends) are fixed by the platform and are only affected by `enabled`.
	 */
	public static var intensity(default, set):Float = 1;

	/** What the device's hardware can do. Cheap, but not free: read it once rather than every frame. */
	public static var capabilities(get, never):HapticCapabilities;

	/** Plays a tap of the given strength. */
	public static function impact(style:ImpactStyle = MEDIUM):Void
	{
		if (enabled)
			MobileTools.backend.impact(style);
	}

	/** Plays a pattern that tells the user a task succeeded, needs attention, or failed. */
	public static function notification(type:NotificationType):Void
	{
		if (enabled)
			MobileTools.backend.notification(type);
	}

	/** Plays a very light tick, meant for changes in a selection. */
	public static function selection():Void
	{
		if (enabled)
			MobileTools.backend.selection();
	}

	/**
	 * Plays a custom pattern, replacing whatever was still playing.
	 * Does nothing when `enabled` is `false` or `intensity` is 0.
	 */
	public static function play(pattern:HapticPattern):Void
	{
		if (!enabled || intensity <= 0 || pattern == null || pattern.events.length == 0)
			return;

		MobileTools.backend.playHapticPattern(intensity < 1 ? pattern.scaled(intensity) : pattern);
	}

	/**
	 * Plays the pattern called `name`: one of `HapticPresets.names`, one you `register()`ed, or one a mod provides.
	 *
	 * @return `false` if there is no such pattern.
	 */
	public static function playNamed(name:String):Bool
	{
		var pattern = HapticLibrary.get(name);

		if (pattern == null)
			return false;

		play(pattern);
		return true;
	}

	/** Stops a pattern that is still playing. */
	public static function stop():Void
	{
		MobileTools.backend.cancelHaptics();
	}

	/**
	 * Makes `pattern` available as `name` for `playNamed()` and for scripts. It replaces a built in pattern with
	 * that name, and can in turn be replaced by a mod.
	 */
	public static function register(name:String, pattern:HapticPattern):Void
	{
		HapticLibrary.define('app', HapticLibrary.PRIORITY_APP, name, pattern);
	}

	/** Removes a pattern added with `register()`. A built in pattern of the same name is visible again. */
	public static function unregister(name:String):Void
	{
		HapticLibrary.remove('app', name);
	}

	/** `true` if `playNamed(name)` would find something. */
	public static function has(name:String):Bool
	{
		return HapticLibrary.has(name);
	}

	/** The pattern called `name`, or `null`. Don't modify it: use `copy()` first. */
	public static function getPattern(name:String):Null<HapticPattern>
	{
		return HapticLibrary.get(name);
	}

	/** Every pattern name available right now, sorted. */
	public static function patternNames():Array<String>
	{
		return HapticLibrary.names();
	}

	private static function set_intensity(value:Float):Float
	{
		intensity = Math.isNaN(value) ? 1 : (value < 0 ? 0 : (value > 1 ? 1 : value));
		return intensity;
	}

	private static function get_capabilities():HapticCapabilities
	{
		return MobileTools.backend.getHapticCapabilities();
	}
}
