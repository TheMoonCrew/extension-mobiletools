package mobiletools;

/**
 * Named haptic patterns, kept in layers so several sources can provide the same name.
 *
 * The highest priority layer that has a name wins. The built in presets sit at the bottom, the app's own
 * patterns (`Haptics.register()`) above them, and mods above that, so a mod can restyle any pattern
 * and disabling it brings the original back.
 */
class HapticLibrary
{
	/** Priority of the built in presets. */
	public static inline var PRIORITY_BUILT_IN:Int = 0;

	/** Priority of patterns registered with `Haptics.register()`. */
	public static inline var PRIORITY_APP:Int = 100;

	/** Priority of the first mod. Later mods add their position to this. */
	public static inline var PRIORITY_MODS:Int = 200;

	private static var layers:Array<Layer> = [];

	/** The pattern called `name` from the highest priority layer that has it, or `null`. */
	public static function get(name:String):Null<HapticPattern>
	{
		ensureBuiltIn();

		var key = normalize(name);
		var best:Null<Layer> = null;

		for (layer in layers)
		{
			if (layer.patterns.exists(key) && (best == null || layer.priority >= best.priority))
				best = layer;
		}

		return best != null ? best.patterns.get(key) : null;
	}

	public static function has(name:String):Bool
	{
		return get(name) != null;
	}

	/** Every available name, without duplicates, sorted. */
	public static function names():Array<String>
	{
		ensureBuiltIn();

		var seen:Map<String, Bool> = new Map();

		for (layer in layers)
		{
			for (key in layer.patterns.keys())
				seen.set(key, true);
		}

		var result = [for (key in seen.keys()) key];
		result.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		return result;
	}

	/** Replaces everything `source` provides. Names are case insensitive. */
	public static function setLayer(source:String, priority:Int, patterns:Map<String, HapticPattern>):Void
	{
		ensureBuiltIn();
		removeLayer(source);

		var normalized:Map<String, HapticPattern> = new Map();

		for (name => pattern in patterns)
			normalized.set(normalize(name), pattern);

		layers.push({source: source, priority: priority, patterns: normalized});
	}

	/** Adds or replaces one pattern in the layer `source`, creating the layer if needed. */
	public static function define(source:String, priority:Int, name:String, pattern:HapticPattern):Void
	{
		ensureBuiltIn();

		var key = normalize(name);

		if (key == '' || key.length > 64)
			throw 'Haptic pattern names must be 1 to 64 characters long';

		for (layer in layers)
		{
			if (layer.source == source)
			{
				layer.patterns.set(key, pattern);
				return;
			}
		}

		layers.push({source: source, priority: priority, patterns: [key => pattern]});
	}

	/** Removes one pattern from the layer `source`. */
	public static function remove(source:String, name:String):Void
	{
		for (layer in layers)
		{
			if (layer.source == source)
				layer.patterns.remove(normalize(name));
		}
	}

	public static function removeLayer(source:String):Void
	{
		layers = layers.filter(function(layer) return layer.source != source);
	}

	/** Removes every layer whose source starts with `prefix`, e.g. `mod:`. */
	public static function removeLayersWithPrefix(prefix:String):Void
	{
		layers = layers.filter(function(layer) return !StringTools.startsWith(layer.source, prefix));
	}

	/** Back to the built in presets only. Mostly for tests. */
	public static function reset():Void
	{
		layers = [];
	}

	private static function ensureBuiltIn():Void
	{
		for (layer in layers)
		{
			if (layer.source == 'built-in')
				return;
		}

		layers.push({source: 'built-in', priority: PRIORITY_BUILT_IN, patterns: normalizeAll(HapticPresets.create())});
	}

	private static function normalizeAll(patterns:Map<String, HapticPattern>):Map<String, HapticPattern>
	{
		var result:Map<String, HapticPattern> = new Map();

		for (name => pattern in patterns)
			result.set(normalize(name), pattern);

		return result;
	}

	private static inline function normalize(name:String):String
	{
		return StringTools.trim(name == null ? '' : name).toLowerCase();
	}
}

private typedef Layer =
{
	var source:String;
	var priority:Int;
	var patterns:Map<String, HapticPattern>;
}
