import Check.*;
import mobiletools.HapticCapabilities;
import mobiletools.HapticLibrary;
import mobiletools.HapticPattern;
import mobiletools.HapticPresets;
import mobiletools.Haptics;
import mobiletools.ImpactStyle;
import mobiletools.MobileTools;
import mobiletools.NotificationType;
import mobiletools.backend.NullBackend;
import mobiletools.mods.ModFiles;
import mobiletools.mods.ModManager;
import mobiletools.scripting.Script;
import sys.FileSystem;

/**
 * Remembers what the haptics code asked the platform to do, so it can be checked without a phone.
 */
class RecordingBackend extends NullBackend
{
	public var patterns:Array<HapticPattern> = [];
	public var impacts:Array<Int> = [];
	public var notifications:Array<Int> = [];
	public var selections:Int = 0;
	public var cancels:Int = 0;
	public var capabilities:HapticCapabilities = {supported: true, amplitudeControl: true, sharpnessControl: false};

	override public function playHapticPattern(pattern:HapticPattern):Void
	{
		patterns.push(pattern);
	}

	override public function cancelHaptics():Void
	{
		cancels++;
	}

	override public function impact(style:ImpactStyle):Void
	{
		impacts.push(style);
	}

	override public function notification(type:NotificationType):Void
	{
		notifications.push(type);
	}

	override public function selection():Void
	{
		selections++;
	}

	override public function getHapticCapabilities():HapticCapabilities
	{
		return capabilities;
	}

	public function clear():Void
	{
		patterns = [];
		impacts = [];
		notifications = [];
		selections = 0;
		cancels = 0;
	}
}

/**
 * Tests for haptic patterns, the pattern library, the `Haptics` class, the script API and mod provided patterns.
 * Run from the repository root:
 *
 *     haxe tests/test.hxml
 */
class HapticTest
{
	static var backend:RecordingBackend = new RecordingBackend();

	static function main():Void
	{
		var original = Sys.getCwd();
		var parent = Sys.getEnv('TEMP') != null ? Sys.getEnv('TEMP') : (Sys.getEnv('TMPDIR') != null ? Sys.getEnv('TMPDIR') : '/tmp');
		var temp = parent + '/mobiletools-haptic-tests-' + Std.int(Sys.time());
		ModFiles.ensureDirectory(temp);
		Sys.setCwd(temp);

		MobileTools.setBackend(backend);

		testPattern();
		testWaveform();
		testSerialization();
		testLibrary();
		testHaptics();
		testScriptApi();
		testMods();

		Sys.setCwd(original);
		deleteRecursive(temp);

		Sys.exit(Check.finish());
	}

	static function reset():Void
	{
		backend.clear();
		Haptics.enabled = true;
		Haptics.intensity = 1;
		HapticLibrary.reset();
	}

	static function deleteRecursive(path:String):Void
	{
		if (!FileSystem.exists(path))
			return;

		if (FileSystem.isDirectory(path))
		{
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(path + '/' + entry);

			FileSystem.deleteDirectory(path);
		}
		else
			FileSystem.deleteFile(path);
	}

	static function write(path:String, content:String):Void
	{
		ModFiles.ensureDirectory(haxe.io.Path.directory(path));
		ModFiles.writeText(path, content);
	}

	// ---------------------------------------------------------------- patterns

	static function testPattern():Void
	{
		var pattern = new HapticPattern('test').tap(0).hold(100, 200, 0.5);

		equals(pattern.name, 'test', 'keeps its name');
		equals(pattern.events.length, 2, 'chaining adds events');
		equals(pattern.events[0].intensity, 1, 'tap defaults to full intensity');
		equals(pattern.events[0].sharpness, 0.5, 'tap defaults to medium sharpness');
		equals(pattern.events[0].duration, 0, 'a tap has no duration');
		equals(pattern.events[1].duration, 200, 'hold keeps its duration');

		var clamped = new HapticPattern().tap(-50, 3, -1);
		equals(clamped.events[0].time, 0, 'negative time is clamped to 0');
		equals(clamped.events[0].intensity, 1, 'intensity above 1 is clamped');
		equals(clamped.events[0].sharpness, 0, 'sharpness below 0 is clamped');

		throwsWith(function() new HapticPattern().tap(Math.NaN), 'must be a number', 'rejects NaN');
		throwsWith(function() new HapticPattern().tap(0, Math.POSITIVE_INFINITY), 'must be a number', 'rejects infinity');
		throwsWith(function() new HapticPattern().hold(29000, 2000), 'at most 30 seconds', 'rejects patterns longer than 30 seconds');
		throwsWith(function()
		{
			var big = new HapticPattern();

			for (i in 0...300)
				big.tap(i);
		}, 'at most 256 events', 'rejects too many events');

		// ramp
		var ramp = new HapticPattern().ramp(0, 400, 0.2, 1, 5);
		equals(ramp.events.length, 5, 'ramp makes one hold per step');
		equals(ramp.events[0].intensity, 0.2, 'ramp starts at from');
		equals(ramp.events[4].intensity, 1, 'ramp ends at to');
		check(ramp.events[1].intensity > ramp.events[0].intensity && ramp.events[2].intensity > ramp.events[1].intensity, 'ramp rises');
		equals(ramp.events[1].time, 80, 'ramp steps follow each other');
		equals(ramp.duration, 400, 'ramp lasts as long as asked');
		throwsWith(function() new HapticPattern().ramp(0, 100, 0, 1, 0), 'between 1 and 64', 'rejects 0 ramp steps');
		equals(new HapticPattern().ramp(0, 100, 0.2, 0.8, 1).events[0].intensity, 0.5, 'a single step ramp uses the middle');

		// repeat
		var repeated = new HapticPattern().tap(0).tap(50).repeat(2, 300);
		equals(repeated.events.length, 6, 'repeat adds copies');
		equals(repeated.events[2].time, 300, 'the first copy is one interval later');
		equals(repeated.events[4].time, 600, 'the second copy is two intervals later');
		equals(new HapticPattern().tap(0).repeat(0, 100).events.length, 1, 'repeat(0) changes nothing');
		throwsWith(function() new HapticPattern().tap(0).repeat(-1, 100), 'count of 0 or more', 'rejects a negative repeat');

		// scaled / stretched / copy
		var base = new HapticPattern('base').tap(100, 0.8).hold(200, 100, 0.4);
		var half = base.scaled(0.5);
		equals(half.events[0].intensity, 0.4, 'scaled multiplies intensity');
		equals(half.events[1].intensity, 0.2, 'scaled multiplies every event');
		equals(base.events[0].intensity, 0.8, 'scaled leaves the original alone');
		equals(half.name, 'base', 'scaled keeps the name');
		equals(new HapticPattern().tap(0, 0.9).scaled(5).events[0].intensity, 1, 'scaled clamps to 1');

		var slow = base.stretched(2);
		equals(slow.events[0].time, 200, 'stretched slows down times');
		equals(slow.events[1].duration, 200, 'stretched slows down durations');
		throwsWith(function() base.stretched(0), 'above 0', 'rejects a stretch of 0');

		var duplicate = base.copy();
		duplicate.tap(900);
		equals(base.events.length, 2, 'a copy is independent');

		// duration: last event end; a tap at 100 with sharpness 0.5 lasts round(35 - 12.5) = 23 ms
		equals(new HapticPattern().tap(100).duration, 123, 'duration includes the length of a final tap');
		equals(new HapticPattern().duration, 0, 'an empty pattern lasts 0');
	}

	// ---------------------------------------------------------------- waveform

	static function testWaveform():Void
	{
		var single = new HapticPattern().tap(0).toWaveform();
		equals(single.timings.join(','), '23', 'a tap becomes one short segment');
		equals(single.amplitudes.join(','), '255', 'full intensity is amplitude 255');

		// Sharper taps are shorter.
		equals(new HapticPattern().tap(0, 1, 1).toWaveform().timings.join(','), '10', 'a sharp tap is 10 ms');
		equals(new HapticPattern().tap(0, 1, 0).toWaveform().timings.join(','), '35', 'a soft tap is 35 ms');

		var two = new HapticPattern().tap(0).tap(100).toWaveform();
		equals(two.timings.join(','), '23,77,23', 'gaps become silent segments');
		equals(two.amplitudes.join(','), '255,0,255', 'silence has amplitude 0');

		var delayed = new HapticPattern().tap(50).toWaveform();
		equals(delayed.timings.join(','), '50,23', 'a late start gets leading silence');
		equals(delayed.amplitudes.join(','), '0,255', 'leading silence is amplitude 0');

		// Overlap: the strongest event wins, and equal neighbours merge.
		var overlap = new HapticPattern().hold(0, 100, 0.5).hold(50, 100, 1).toWaveform();
		equals(overlap.timings.join(','), '50,100', 'overlapping events are merged');
		equals(overlap.amplitudes.join(','), '128,255', 'the stronger event wins where they overlap');

		equals(new HapticPattern().hold(0, 100, 0.5).toWaveform(0.5).amplitudes.join(','), '64', 'scale reduces the amplitude');
		equals(new HapticPattern().hold(0, 100, 0.001).toWaveform().amplitudes.join(','), '1', 'a faint event still vibrates');
		equals(new HapticPattern().hold(0, 100, 0).toWaveform().amplitudes.join(','), '0', 'zero intensity is silent');
		equals(new HapticPattern().toWaveform().timings.length, 0, 'an empty pattern has no segments');
		equals(new HapticPattern().tap(50).toWaveformString(), '50:0,23:255', 'toWaveformString format');
		equals(new HapticPattern().toWaveformString(), '', 'an empty pattern gives an empty string');

		// Whatever the order events were added in, the output is time ordered.
		var unordered = new HapticPattern().tap(200).tap(0).toWaveform();
		equals(unordered.timings.join(','), '23,177,23', 'event order does not matter');
	}

	// ---------------------------------------------------------------- serialization

	static function testSerialization():Void
	{
		var pattern = new HapticPattern('round').tap(0, 1, 0.9).hold(100, 200, 0.5, 0.25);
		var back = HapticPattern.fromJson(pattern.toJson());

		equals(back.name, 'round', 'the name survives JSON');
		equals(back.events.length, 2, 'events survive JSON');
		equals(back.events[1].duration, 200, 'durations survive JSON');
		equals(back.events[1].sharpness, 0.25, 'sharpness survives JSON');
		equals(HapticPattern.fromJson(pattern.toJson(true)).events.length, 2, 'pretty JSON loads too');

		var loaded = HapticPattern.fromJson('{"events": [{"time": 10}]}');
		equals(loaded.events[0].intensity, 1, 'intensity defaults to 1 when loading');
		equals(loaded.events[0].sharpness, 0.5, 'sharpness defaults to 0.5 when loading');
		equals(loaded.events[0].duration, 0, 'duration defaults to 0 when loading');
		equals(HapticPattern.fromJson('{"events": []}', 'given').name, 'given', 'a name can be passed in');
		equals(HapticPattern.fromJson('{"name": "inside", "events": []}', 'file').name, 'file', 'the passed name wins over the one inside');
		equals(HapticPattern.fromJson('{"name": "inside", "events": []}').name, 'inside', 'the name inside is used when none is passed');
		equals(HapticPattern.fromJson('{"events": [{"time": 0, "intensity": 7}]}').events[0].intensity, 1, 'loading clamps intensity');

		throwsWith(function() HapticPattern.fromJson('{not json'), 'not valid JSON', 'rejects broken JSON');
		throwsWith(function() HapticPattern.fromJson('[]'), 'must be an object', 'rejects a list');
		throwsWith(function() HapticPattern.fromJson('{}'), '"events" list', 'rejects a missing events list');
		throwsWith(function() HapticPattern.fromJson('{"events": 3}'), '"events" list', 'rejects events that are not a list');
		throwsWith(function() HapticPattern.fromJson('{"events": [5]}'), 'must be an object', 'rejects an event that is not an object');
		throwsWith(function() HapticPattern.fromJson('{"events": [{"intensity": 1}]}'), 'needs a "time"', 'rejects an event without time');
		throwsWith(function() HapticPattern.fromJson('{"events": [{"time": "soon"}]}'), 'must be a number', 'rejects a non-numeric time');
		throwsWith(function() HapticPattern.fromJson('{"events": [{"time": 40000}]}'), 'at most 30 seconds', 'loading enforces the duration limit');

		// The compact form handed to iOS
		equals(new HapticPattern().tap(0, 1, 0.5).hold(100, 200, 0.5, 0.25).toCompact(), '0:0:1:0.5,100:200:0.5:0.25', 'compact format');
		equals(new HapticPattern().tap(0.00001, 0.123456, 1).toCompact(), '0:0:0.123:1', 'compact format rounds to three decimals');
		equals(new HapticPattern().toCompact(), '', 'an empty pattern is an empty string');
	}

	// ---------------------------------------------------------------- library

	static function testLibrary():Void
	{
		reset();

		var names = HapticPresets.names;
		check(names.length >= 10, 'there are built in presets');

		for (name in ['double-tap', 'triple-tap', 'knock', 'pulse', 'heartbeat', 'buzz', 'alarm', 'rumble', 'explosion', 'ramp-up', 'ramp-down'])
			check(Haptics.has(name), 'built in "$name" exists');

		for (name in names)
		{
			var pattern = HapticLibrary.get(name);
			check(pattern != null && pattern.events.length > 0 && pattern.duration <= HapticPattern.MAX_DURATION, 'preset "$name" is a valid pattern');
		}

		var sorted = names.copy();
		sorted.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		equals(names.join(','), sorted.join(','), 'preset names are sorted');
		equals(HapticLibrary.get('heartbeat').events.length, 6, 'heartbeat has three beats of two events');
		equals(HapticLibrary.get('  HeartBeat ') != null, true, 'names are case insensitive and trimmed');
		check(!Haptics.has('nonexistent'), 'unknown names are not found');

		// Layers: higher priority wins, and removing a layer brings the lower one back.
		var loud = new HapticPattern('loud').tap(0);
		HapticLibrary.define('layer-a', 50, 'heartbeat', loud);
		equals(HapticLibrary.get('heartbeat'), loud, 'a layer above the built in ones wins');

		var louder = new HapticPattern('louder').tap(0).tap(10);
		HapticLibrary.define('layer-b', 300, 'HEARTBEAT', louder);
		equals(HapticLibrary.get('heartbeat'), louder, 'the highest priority wins');

		HapticLibrary.removeLayer('layer-b');
		equals(HapticLibrary.get('heartbeat'), loud, 'removing a layer reveals the next one');
		HapticLibrary.removeLayer('layer-a');
		equals(HapticLibrary.get('heartbeat').events.length, 6, 'the built in pattern comes back');

		HapticLibrary.define('mod:one', 200, 'a', loud);
		HapticLibrary.define('mod:two', 201, 'b', loud);
		HapticLibrary.define('keep', 100, 'c', loud);
		HapticLibrary.removeLayersWithPrefix('mod:');
		check(!Haptics.has('a') && !Haptics.has('b') && Haptics.has('c'), 'removeLayersWithPrefix only removes matching layers');
		check(HapticLibrary.names().indexOf('c') >= 0 && HapticLibrary.names().indexOf('heartbeat') >= 0, 'names() lists every layer');

		throwsWith(function() HapticLibrary.define('x', 1, '   ', loud), '1 to 64', 'rejects an empty name');
		throwsWith(function() HapticLibrary.define('x', 1, [for (i in 0...65) 'a'].join(''), loud), '1 to 64', 'rejects a name that is too long');

		// App registration through Haptics
		Haptics.register('mine', loud);
		check(Haptics.has('mine') && Haptics.getPattern('mine') == loud, 'register() makes a pattern available');
		Haptics.register('heartbeat', loud);
		equals(Haptics.getPattern('heartbeat'), loud, 'register() can replace a built in pattern');
		Haptics.unregister('heartbeat');
		equals(Haptics.getPattern('heartbeat').events.length, 6, 'unregister() brings the built in one back');
		check(Haptics.patternNames().indexOf('mine') >= 0, 'patternNames() includes registered patterns');
	}

	// ---------------------------------------------------------------- Haptics

	static function testHaptics():Void
	{
		reset();

		var pattern = new HapticPattern().tap(0, 0.8).hold(100, 100, 0.4);
		Haptics.play(pattern);
		equals(backend.patterns.length, 1, 'play() reaches the backend');
		equals(backend.patterns[0], pattern, 'an unscaled pattern is passed on as is');

		backend.clear();
		Haptics.intensity = 0.5;
		Haptics.play(pattern);
		equals(backend.patterns[0].events[0].intensity, 0.4, 'intensity scales the pattern');
		equals(pattern.events[0].intensity, 0.8, 'the original pattern is not modified');

		backend.clear();
		Haptics.intensity = 0;
		Haptics.play(pattern);
		equals(backend.patterns.length, 0, 'intensity 0 plays nothing');
		Haptics.intensity = 7;
		equals(Haptics.intensity, 1, 'intensity is clamped to 1');
		Haptics.intensity = -2;
		equals(Haptics.intensity, 0, 'intensity is clamped to 0');
		Haptics.intensity = Math.NaN;
		equals(Haptics.intensity, 1, 'a NaN intensity falls back to 1');

		Haptics.play(null);
		Haptics.play(new HapticPattern());
		equals(backend.patterns.length, 0, 'null and empty patterns are ignored');

		// enabled is a master switch
		Haptics.enabled = false;
		Haptics.play(pattern);
		Haptics.impact(HEAVY);
		Haptics.notification(ERROR);
		Haptics.selection();
		check(Haptics.playNamed('heartbeat'), 'playNamed still finds the pattern while disabled');
		equals(backend.patterns.length + backend.impacts.length + backend.notifications.length + backend.selections, 0, 'enabled = false silences everything');
		Haptics.enabled = true;

		Haptics.impact(HEAVY);
		Haptics.impact();
		Haptics.notification(WARNING);
		Haptics.selection();
		equals(backend.impacts.join(','), '2,1', 'impact reaches the backend, default is medium');
		equals(backend.notifications.join(','), '1', 'notification reaches the backend');
		equals(backend.selections, 1, 'selection reaches the backend');

		backend.clear();
		check(Haptics.playNamed('knock'), 'playNamed finds a built in pattern');
		equals(backend.patterns.length, 1, 'playNamed plays it');
		check(!Haptics.playNamed('does-not-exist'), 'playNamed returns false for an unknown name');
		equals(backend.patterns.length, 1, 'and plays nothing');

		Haptics.stop();
		equals(backend.cancels, 1, 'stop() cancels');

		backend.capabilities = {supported: true, amplitudeControl: false, sharpnessControl: true};
		equals(Haptics.capabilities.amplitudeControl, false, 'capabilities come from the backend');
		equals(Haptics.capabilities.sharpnessControl, true, 'capabilities come from the backend (sharpness)');

		check(HapticCapabilitiesTools.fromBits(1 | 4).supported && !HapticCapabilitiesTools.fromBits(1 | 4).amplitudeControl && HapticCapabilitiesTools.fromBits(1 | 4).sharpnessControl, 'capability bits are decoded');
		check(!HapticCapabilitiesTools.fromBits(0).supported, 'no bits means unsupported');
		check(!HapticCapabilitiesTools.none().supported, 'none() is unsupported');
	}

	// ---------------------------------------------------------------- scripts

	static function testScriptApi():Void
	{
		reset();

		function run(code:String):Dynamic
		{
			return Script.fromString('function main() { $code }', 'script').call('main');
		}

		equals(run('return haptics.play("heartbeat");'), true, 'haptics.play returns true for a known pattern');
		equals(backend.patterns.length, 1, 'haptics.play reaches the backend');
		equals(run('return haptics.play("nope");'), false, 'haptics.play returns false for an unknown pattern');
		equals(run('return haptics.has("knock") && !haptics.has("nope");'), true, 'haptics.has');
		check((run('return haptics.names();') : Array<String>).indexOf('rumble') >= 0, 'haptics.names lists the presets');
		equals(run('return haptics.isEnabled();'), true, 'haptics.isEnabled');
		equals(run('return haptics.capabilities().supported;'), true, 'haptics.capabilities');

		backend.clear();
		run('haptics.pattern().tap(0).hold(100, 200, 0.5).play();');
		equals(backend.patterns.length, 1, 'a built pattern plays');
		equals(backend.patterns[0].events.length, 2, 'it has the events the script added');
		equals(backend.patterns[0].events[0].intensity, 1, 'optional arguments get their defaults');
		equals(backend.patterns[0].events[1].intensity, 0.5, 'given arguments are used');

		backend.clear();
		run('haptics.pattern("named").tap(0).ramp(0, 100, 0, 1).repeat(1, 500).play();');
		equals(backend.patterns[0].name, 'named', 'a pattern can be named');
		equals(backend.patterns[0].events.length, 18, 'ramp (8 steps) and repeat chain');

		backend.clear();
		run('haptics.fromJson(\'{"events":[{"time":0,"intensity":0.3}]}\').play();');
		equals(backend.patterns[0].events[0].intensity, 0.3, 'haptics.fromJson');
		backend.clear();
		run('haptics.fromData({events: [{time: 5}, {time: 50, duration: 100}]}).play();');
		equals(backend.patterns[0].events.length, 2, 'haptics.fromData');
		equals(run('return haptics.pattern().tap(0).hold(100, 200).duration();'), 300, 'builder duration()');
		check((run('return haptics.pattern().tap(0).toJson();') : String).indexOf('"events"') >= 0, 'builder toJson()');

		// define saves a pattern for later
		run('haptics.define("zap", haptics.pattern().tap(0, 1, 1).tap(60, 0.5, 1));');
		backend.clear();
		check(Haptics.playNamed('zap'), 'a pattern saved by a script can be played by name');
		equals(backend.patterns[0].events.length, 2, 'with its events');
		equals(run('return haptics.play("zap");'), true, 'and from scripts too');

		// the old mobile.* calls still work
		backend.clear();
		run('mobile.impact("heavy"); mobile.notification("success"); mobile.selection(); haptics.impact("soft"); haptics.notification("error"); haptics.selection();');
		equals(backend.impacts.join(','), '2,3', 'impact from both APIs');
		equals(backend.notifications.join(','), '0,2', 'notification from both APIs');
		equals(backend.selections, 2, 'selection from both APIs');

		Haptics.stop();
		backend.cancels = 0;
		run('haptics.stop();');
		equals(backend.cancels, 1, 'haptics.stop');

		// validation and limits
		throwsWith(function() run('haptics.pattern().tap();'), 'Missing argument 1', 'tap needs a time');
		throwsWith(function() run('haptics.pattern().tap("now");'), 'must be a number', 'arguments must be numbers');
		throwsWith(function() run('haptics.pattern().hold(0);'), 'Missing argument 2', 'hold needs a duration');
		throwsWith(function() run('haptics.impact("gentle");'), 'Unknown impact style', 'impact styles are checked');
		throwsWith(function() run('haptics.notification("loud");'), 'Unknown notification type', 'notification types are checked');
		throwsWith(function() run('var p = haptics.pattern(); for (i in 0...300) p.tap(i);'), 'at most 256 events', 'scripts cannot build huge patterns');
		throwsWith(function() run('haptics.pattern().hold(0, 31000);'), 'at most 30 seconds', 'scripts cannot build endless patterns');
		throwsWith(function() run('haptics.fromJson("{bad");'), 'not valid JSON', 'bad JSON from a script is reported');
		throwsWith(function() run('haptics.define("x", {getPattern: function() return 5});'), 'Expected a pattern', 'define refuses a made up builder');
		throwsWith(function() run('haptics.define("x", 5);'), 'Expected a pattern', 'define refuses a non-builder');
		throwsWith(function() run('haptics.define("", haptics.pattern().tap(0));'), '1 to 64', 'define checks the name');

		// scripts cannot flip the user's settings
		run('haptics.enabled = false; haptics.intensity = 0;');
		equals(Haptics.enabled, true, 'a script cannot disable haptics');
		equals(Haptics.intensity, 1, 'a script cannot change the intensity');
		throwsWith(function() run('Haptics.enabled = false;'), 'Unknown variable', 'the Haptics class is not exposed');
		throwsWith(function() run('return HapticLibrary.names();'), 'Unknown variable', 'the library class is not exposed');

		// the user's settings apply to scripts
		backend.clear();
		Haptics.enabled = false;
		run('haptics.play("knock"); haptics.pattern().tap(0).play(); haptics.impact("heavy");');
		equals(backend.patterns.length + backend.impacts.length, 0, 'enabled = false silences scripts');
		Haptics.enabled = true;
	}

	// ---------------------------------------------------------------- mods

	static function testMods():Void
	{
		reset();

		var base = FileSystem.fullPath('.');
		var root = base + '/mods-root';

		// pack-a: a pattern file, a restyled built in pattern, a named one, plus script saved ones.
		write(root + '/pack-a/mod.json', '{"name": "Pack A"}');
		write(root + '/pack-a/haptics/boom.json', '{"events": [{"time": 0, "intensity": 1}, {"time": 100, "duration": 200, "intensity": 0.5}]}');
		write(root + '/pack-a/haptics/heartbeat.json', '{"events": [{"time": 0}]}');
		write(root + '/pack-a/haptics/file-name.JSON', '{"name": "Custom Name", "events": [{"time": 0}]}');
		write(root + '/pack-a/haptics/broken.json', '{"events": "nope"}');
		write(root + '/pack-a/haptics/readme.txt', 'not a pattern');
		write(root + '/pack-a/scripts/main.hx', 'haptics.define("top-level", haptics.pattern().tap(0));\nfunction onLoad() { haptics.define("late", haptics.pattern().tap(0).tap(50)); }\nfunction zap() { return haptics.play("boom"); }');

		// pack-b: provides the same names with different content.
		write(root + '/pack-b/mod.json', '{"name": "Pack B"}');
		write(root + '/pack-b/haptics/boom.json', '{"events": [{"time": 0}, {"time": 10}, {"time": 20}]}');

		var errors:Array<String> = [];
		ModManager.onError = function(source, message) errors.push('$source: $message');
		ModManager.onLog = function(source, message) {};
		ModManager.stateFile = base + '/state.json';
		ModManager.addRoot(root);
		ModManager.init();

		check(!Haptics.has('boom'), 'nothing is provided before a mod is enabled');
		equals(Haptics.getPattern('heartbeat').events.length, 6, 'the built in heartbeat is untouched');

		check(ModManager.enable('pack-a'), 'a mod with haptic files enables');
		check(Haptics.has('boom'), 'a mod provides a pattern from haptics/*.json');
		equals(Haptics.getPattern('boom').events.length, 2, 'with the file contents');
		equals(Haptics.getPattern('boom').events[1].duration, 200, 'including durations');
		equals(Haptics.getPattern('heartbeat').events.length, 1, 'a mod can restyle a built in pattern');
		check(Haptics.has('custom name'), 'the name inside a file is used (case insensitive)');
		check(!Haptics.has('file-name'), 'and replaces the file name');
		check(!Haptics.has('readme'), 'files that are not .json are ignored');
		check(!Haptics.has('broken'), 'a broken pattern file is skipped');
		equals(errors.filter(e -> e.indexOf('pack-a: haptics/broken.json') == 0 && e.indexOf('"events" list') >= 0).length, 1, 'a broken pattern file is reported once');
		check(ModManager.isEnabled('pack-a'), 'a broken pattern file does not stop the mod');
		check(Haptics.has('top-level'), 'a pattern saved at the top of a script is kept');
		check(Haptics.has('late'), 'a pattern saved in onLoad is kept');

		backend.clear();
		check(ModManager.call('zap')[0] == true, 'a mod script can play its own pattern');
		equals(backend.patterns[0].events.length, 2, 'the mod pattern was played');

		// two mods: the later one wins, and move() changes who is later.
		check(ModManager.enable('pack-b'), 'a second mod enables');
		equals(Haptics.getPattern('boom').events.length, 3, 'the later mod wins a shared name');
		ModManager.move('pack-b', 0);
		equals(Haptics.getPattern('boom').events.length, 2, 'move() changes the winner');
		check(Haptics.has('heartbeat') && Haptics.getPattern('heartbeat').events.length == 1, 'patterns only one mod has are unaffected');

		// app registered patterns sit below mods
		Haptics.register('boom', new HapticPattern().tap(0));
		equals(Haptics.getPattern('boom').events.length, 2, 'mods win over the app\'s own patterns');
		Haptics.unregister('boom');

		// reload keeps things
		ModManager.reload();
		check(Haptics.has('boom') && Haptics.has('late') && Haptics.has('top-level'), 'patterns are back after reload()');

		// disabling gives everything back
		ModManager.disable('pack-a');
		check(!Haptics.has('late') && !Haptics.has('top-level') && !Haptics.has('custom name'), 'disabling a mod removes its patterns, including script saved ones');
		equals(Haptics.getPattern('heartbeat').events.length, 6, 'the built in pattern is back');
		equals(Haptics.getPattern('boom').events.length, 3, 'the other mod\'s pattern shows through');
		ModManager.disable('pack-b');
		check(!Haptics.has('boom'), 'no mod, no pattern');

		// A mod cannot take the user's settings
		write(root + '/pack-c/mod.json', '{"name": "Pack C"}');
		write(root + '/pack-c/scripts/main.hx', 'function onLoad() { haptics.enabled = false; haptics.intensity = 0; }');
		ModManager.reload();
		check(ModManager.enable('pack-c'), 'a mod that tries to change the settings still loads');
		check(Haptics.enabled && Haptics.intensity == 1, 'but cannot change them');
	}
}
