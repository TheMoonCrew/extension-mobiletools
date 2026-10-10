package mobiletools;

import haxe.Json;

/**
 * One moment of a `HapticPattern`.
 */
typedef HapticEvent =
{
	/** Milliseconds after the start of the pattern. */
	var time:Float;

	/** Milliseconds the vibration lasts. `0` is a short transient tap. */
	var duration:Float;

	/** Strength from 0 (nothing) to 1 (full). */
	var intensity:Float;

	/** Feel from 0 (soft, dull) to 1 (crisp, sharp). Only used where the hardware supports it (iOS). */
	var sharpness:Float;
}

/**
 * The result of `HapticPattern.toWaveform()`: alternating segments of `timings[i]` milliseconds at `amplitudes[i]` (0-255).
 */
typedef HapticWaveform =
{
	var timings:Array<Int>;
	var amplitudes:Array<Int>;
}

/**
 * A custom vibration described as a list of events, in the spirit of Apple's Core Haptics.
 *
 * Build one in code, or load it from JSON so it can ship in a mod:
 *
 * ```haxe
 * var pattern = new HapticPattern('knock')
 *     .tap(0, 1, 0.9)                       // time, intensity, sharpness
 *     .tap(120, 0.7, 0.9)
 *     .hold(300, 200, 0.5)                  // time, duration, intensity
 *     .ramp(600, 400, 0.2, 1);              // time, duration, from, to
 *
 * Haptics.play(pattern);
 * ```
 *
 * Every value is checked as it is added, so a pattern coming from an untrusted mod can't
 * ask for more than `MAX_EVENTS` events or `MAX_DURATION` milliseconds.
 */
class HapticPattern
{
	/** Most events one pattern may hold. */
	public static inline var MAX_EVENTS:Int = 256;

	/** Longest a pattern may last, in milliseconds. */
	public static inline var MAX_DURATION:Float = 30000;

	/** Optional name, used when saving to a library. */
	public var name:Null<String>;

	/** The events, in the order they were added. */
	public var events(default, null):Array<HapticEvent> = [];

	/** When the last event ends, in milliseconds. */
	public var duration(get, never):Float;

	public function new(?name:String)
	{
		this.name = name;
	}

	// ---------------------------------------------------------------- building

	/** A short tap at `time` milliseconds. */
	public function tap(time:Float, intensity:Float = 1, sharpness:Float = 0.5):HapticPattern
	{
		return add(time, 0, intensity, sharpness);
	}

	/** A steady vibration starting at `time` that lasts `duration` milliseconds. */
	public function hold(time:Float, duration:Float, intensity:Float = 1, sharpness:Float = 0.5):HapticPattern
	{
		return add(time, Math.max(1, duration), intensity, sharpness);
	}

	/**
	 * A vibration that fades from `from` to `to` over `duration` milliseconds.
	 * It is made of `steps` short holds, since an event has a single intensity.
	 */
	public function ramp(time:Float, duration:Float, from:Float, to:Float, steps:Int = 8, sharpness:Float = 0.5):HapticPattern
	{
		if (steps < 1 || steps > 64)
			throw 'A ramp needs between 1 and 64 steps';

		var length = Math.max(1, duration) / steps;

		for (i in 0...steps)
		{
			var progress = steps == 1 ? 0.5 : i / (steps - 1);
			add(time + i * length, length, from + (to - from) * progress, sharpness);
		}

		return this;
	}

	/**
	 * Adds `count` more copies of everything added so far, each `interval` milliseconds after the previous one.
	 */
	public function repeat(count:Int, interval:Float):HapticPattern
	{
		check(interval, 'interval');

		if (count < 0)
			throw 'repeat() needs a count of 0 or more';

		var original = events.copy();

		for (round in 1...count + 1)
		{
			for (event in original)
				add(event.time + interval * round, event.duration, event.intensity, event.sharpness);
		}

		return this;
	}

	/** A copy with every intensity multiplied by `factor` (clamped to 0-1). */
	public function scaled(factor:Float):HapticPattern
	{
		check(factor, 'factor');

		var result = new HapticPattern(name);

		for (event in events)
			result.events.push({time: event.time, duration: event.duration, intensity: clamp(event.intensity * factor), sharpness: event.sharpness});

		return result;
	}

	/** A copy played `factor` times slower (above 1) or faster (below 1). */
	public function stretched(factor:Float):HapticPattern
	{
		check(factor, 'factor');

		if (factor <= 0)
			throw 'stretched() needs a factor above 0';

		var result = new HapticPattern(name);

		for (event in events)
			result.add(event.time * factor, event.duration * factor, event.intensity, event.sharpness);

		return result;
	}

	public function copy():HapticPattern
	{
		return scaled(1);
	}

	private function add(time:Float, duration:Float, intensity:Float, sharpness:Float):HapticPattern
	{
		check(time, 'time');
		check(duration, 'duration');
		check(intensity, 'intensity');
		check(sharpness, 'sharpness');

		if (events.length >= MAX_EVENTS)
			throw 'A haptic pattern can have at most $MAX_EVENTS events';

		var start = Math.max(0, time);
		var length = Math.max(0, duration);

		if (start + length > MAX_DURATION)
			throw 'A haptic pattern can last at most ${Std.int(MAX_DURATION / 1000)} seconds';

		events.push({time: start, duration: length, intensity: clamp(intensity), sharpness: clamp(sharpness)});
		return this;
	}

	private static function check(value:Float, what:String):Void
	{
		if (Math.isNaN(value) || !Math.isFinite(value))
			throw 'Haptic $what must be a number';
	}

	private static inline function clamp(value:Float):Float
	{
		return value < 0 ? 0 : (value > 1 ? 1 : value);
	}

	private function get_duration():Float
	{
		var end = 0.0;

		for (event in events)
			end = Math.max(end, event.time + effectiveDuration(event));

		return end;
	}

	// ---------------------------------------------------------------- loading and saving

	/**
	 * Builds a pattern from a plain object, such as parsed JSON:
	 * `{name: "knock", events: [{time: 0, intensity: 1, sharpness: 0.9}, {time: 150, duration: 200}]}`
	 *
	 * Only `time` is required in an event: `duration` defaults to 0 (a tap), `intensity` to 1 and `sharpness` to 0.5.
	 * Out of range intensities are clamped.
	 *
	 * @throws String when the data is malformed or goes over the limits.
	 */
	public static function fromData(data:Dynamic, ?name:String):HapticPattern
	{
		if (data == null || Type.typeof(data) != TObject)
			throw 'A haptic pattern must be an object with an "events" list';

		var declared:Dynamic = Reflect.field(data, 'name');
		var pattern = new HapticPattern(name != null ? name : (Std.isOfType(declared, String) ? declared : null));
		var list:Dynamic = Reflect.field(data, 'events');

		if (list == null || !Std.isOfType(list, Array))
			throw 'A haptic pattern must have an "events" list';

		for (item in (list : Array<Dynamic>))
		{
			if (item == null || Type.typeof(item) != TObject)
				throw 'Every haptic event must be an object';

			pattern.add(number(item, 'time', null), number(item, 'duration', 0), number(item, 'intensity', 1), number(item, 'sharpness', 0.5));
		}

		return pattern;
	}

	/** Like `fromData()`, from JSON text. */
	public static function fromJson(json:String, ?name:String):HapticPattern
	{
		var data:Dynamic;

		try
		{
			data = Json.parse(json);
		}
		catch (e:Dynamic)
		{
			throw 'Haptic pattern is not valid JSON: ' + Std.string(e);
		}

		return fromData(data, name);
	}

	/** The pattern as a plain object, ready for `Json.stringify`. */
	public function toData():Dynamic
	{
		var data:Dynamic = {events: [for (event in events) {time: event.time, duration: event.duration, intensity: event.intensity, sharpness: event.sharpness}]};

		if (name != null)
			data.name = name;

		return data;
	}

	public function toJson(pretty:Bool = false):String
	{
		return Json.stringify(toData(), null, pretty ? '  ' : null);
	}

	private static function number(item:Dynamic, field:String, fallback:Null<Float>):Float
	{
		var value:Dynamic = Reflect.field(item, field);

		if (value == null)
		{
			if (fallback == null)
				throw 'Every haptic event needs a "$field"';

			return fallback;
		}

		if (!Std.isOfType(value, Float))
			throw 'Haptic event "$field" must be a number';

		return value;
	}

	// ---------------------------------------------------------------- for the platform backends

	/** How long a tap lasts on hardware that can only turn the motor on and off: crisp taps are shorter. */
	private static function transientLength(sharpness:Float):Float
	{
		return Math.round(35 - 25 * sharpness);
	}

	private static function effectiveDuration(event:HapticEvent):Float
	{
		return event.duration > 0 ? event.duration : transientLength(event.sharpness);
	}

	/**
	 * The pattern as text for the iOS backend: `time:duration:intensity:sharpness` per event, joined by commas.
	 */
	public function toCompact():String
	{
		return [for (event in events) [event.time, event.duration, event.intensity, event.sharpness].map(round).join(':')].join(',');
	}

	/**
	 * Flattens the events into a waveform for hardware that controls one amplitude at a time (Android).
	 * Where events overlap, the strongest one wins.
	 *
	 * @param scale Multiplier for every intensity, 0-1.
	 */
	public function toWaveform(scale:Float = 1):HapticWaveform
	{
		var spans:Array<{start:Int, end:Int, level:Float}> = [];
		var bounds:Array<Int> = [];

		for (event in events)
		{
			var start = Math.round(event.time);
			var end = Std.int(Math.max(start + 1, Math.round(event.time + effectiveDuration(event))));
			spans.push({start: start, end: end, level: clamp(event.intensity * scale)});
			bounds.push(start);
			bounds.push(end);
		}

		bounds.sort(function(a, b) return a - b);

		var timings:Array<Int> = [];
		var amplitudes:Array<Int> = [];

		function push(length:Int, amplitude:Int):Void
		{
			if (length <= 0)
				return;

			// Neighbours with the same strength are one segment.
			if (amplitudes.length > 0 && amplitudes[amplitudes.length - 1] == amplitude)
				timings[timings.length - 1] += length;
			else
			{
				timings.push(length);
				amplitudes.push(amplitude);
			}
		}

		if (bounds.length == 0)
			return {timings: timings, amplitudes: amplitudes};

		// Silence before the first event.
		push(bounds[0], 0);

		for (i in 0...bounds.length - 1)
		{
			var from = bounds[i];
			var to = bounds[i + 1];

			if (to <= from)
				continue;

			var level = 0.0;

			for (span in spans)
			{
				if (span.start <= from && span.end >= to)
					level = Math.max(level, span.level);
			}

			push(to - from, level > 0 ? Std.int(Math.max(1, Math.round(level * 255))) : 0);
		}

		return {timings: timings, amplitudes: amplitudes};
	}

	/** `toWaveform()` as `milliseconds:amplitude` pairs joined by commas, for the Android backend. */
	public function toWaveformString(scale:Float = 1):String
	{
		var waveform = toWaveform(scale);
		return [for (i in 0...waveform.timings.length) waveform.timings[i] + ':' + waveform.amplitudes[i]].join(',');
	}

	private static function round(value:Float):String
	{
		// Three decimals is plenty and keeps the text free of exponents.
		return Std.string(Math.round(value * 1000) / 1000);
	}
}
