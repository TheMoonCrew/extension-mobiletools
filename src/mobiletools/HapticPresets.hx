package mobiletools;

/**
 * Ready made patterns, available by name through `Haptics.playNamed()`.
 *
 * Mods can replace any of them by shipping a pattern with the same name.
 */
class HapticPresets
{
	/** Names of the built in patterns. */
	public static var names(get, never):Array<String>;

	/** A fresh copy of every built in pattern. */
	public static function create():Map<String, HapticPattern>
	{
		var presets:Map<String, HapticPattern> = new Map();

		function add(pattern:HapticPattern):Void
		{
			presets.set(pattern.name, pattern);
		}

		add(new HapticPattern('double-tap').tap(0, 1, 0.7).tap(110, 0.8, 0.7));
		add(new HapticPattern('triple-tap').tap(0, 0.6, 0.7).tap(100, 0.8, 0.7).tap(200, 1, 0.7));
		add(new HapticPattern('knock').tap(0, 1, 0.9).tap(90, 0.8, 0.9));
		add(new HapticPattern('pulse').tap(0, 0.5, 0.3).repeat(3, 130));
		add(new HapticPattern('heartbeat').tap(0, 1, 0.4).tap(140, 0.7, 0.3).repeat(2, 800));
		add(new HapticPattern('buzz').hold(0, 300, 1, 0.8));
		add(new HapticPattern('alarm').hold(0, 150, 1, 0.8).repeat(2, 250));
		add(new HapticPattern('rumble').hold(0, 400, 0.6, 0.1).ramp(400, 300, 0.6, 0, 6, 0.1));
		add(new HapticPattern('explosion').tap(0, 1, 1).ramp(30, 450, 1, 0, 10, 0.2));
		add(new HapticPattern('ramp-up').ramp(0, 500, 0.1, 1, 10, 0.5));
		add(new HapticPattern('ramp-down').ramp(0, 500, 1, 0.1, 10, 0.5));

		return presets;
	}

	private static function get_names():Array<String>
	{
		var result = [for (name in create().keys()) name];
		result.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		return result;
	}
}
