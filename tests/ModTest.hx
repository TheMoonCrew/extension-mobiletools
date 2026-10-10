import mobiletools.mods.Mod;
import mobiletools.mods.ModFiles;
import mobiletools.mods.ModInfo;
import mobiletools.mods.ModManager;
import mobiletools.scripting.Script;
import sys.FileSystem;

/**
 * Tests for the scripting and modding system. Run from the repository root:
 *
 *     haxe tests/test.hxml
 *
 * It works inside a temporary folder that is deleted afterwards.
 */
class ModTest
{
	static var failures:Int = 0;
	static var checks:Int = 0;

	static function check(condition:Bool, description:String):Void
	{
		checks++;

		if (!condition)
		{
			failures++;
			Sys.println('FAIL: $description');
		}
	}

	static function equals(actual:Dynamic, expected:Dynamic, description:String):Void
	{
		check(actual == expected, '$description (expected "$expected", got "$actual")');
	}

	static function throwsWith(action:Void->Void, expectedPart:String, description:String):Void
	{
		try
		{
			action();
			check(false, '$description (did not throw)');
		}
		catch (e:Dynamic)
		{
			check(Std.string(e).indexOf(expectedPart) >= 0, '$description (error was "$e", expected it to contain "$expectedPart")');
		}
	}

	static function write(path:String, content:String):Void
	{
		ModFiles.ensureDirectory(haxe.io.Path.directory(path));
		ModFiles.writeText(path, content);
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

	// Nothing else uses it, and Haxe drops unused classes: scripts can only create what the app contains.
	@:keep static var keptForScripts = haxe.ds.ObjectMap;

	static function main():Void
	{
		// Desktop paths are relative to the working directory, so give the tests a private one.
		var original = Sys.getCwd();
		var parent = Sys.getEnv('TEMP') != null ? Sys.getEnv('TEMP') : (Sys.getEnv('TMPDIR') != null ? Sys.getEnv('TMPDIR') : '/tmp');
		var temp = parent + '/mobiletools-tests-' + Std.int(Sys.time());
		ModFiles.ensureDirectory(temp);
		Sys.setCwd(temp);

		testScripts();
		testSandbox();
		testPathSafety();
		testMods();

		Sys.setCwd(original);
		deleteRecursive(temp);

		Sys.println(failures == 0 ? 'OK: $checks checks passed' : '$failures of $checks checks FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}

	// ---------------------------------------------------------------- scripting

	static function testScripts():Void
	{
		var script = Script.fromString('var count = 0; function add(a, b) { count++; return a + b; } function twice(x) return x * 2;', 'calc');

		equals(script.call('add', [2, 3]), 5, 'calls a script function');
		equals(script.call('twice', [21]), 42, 'calls a second function');
		equals(script.get('count'), 1, 'reads a script variable');
		check(script.has('add'), 'has() finds a function');
		check(!script.has('nope'), 'has() is false for an unknown function');
		equals(script.call('nope'), null, 'calling a missing function returns null');

		script.set('injected', 7);
		equals(Script.fromString('function f() return injected + 1;', 'g', ['injected' => 9]).call('f'), 10, 'globals are visible to the script');

		equals(Script.fromString('function f() return Std.string(Math.floor(2.7)) + StringTools.trim("  x ");', 's').call('f'), '2x', 'Std, Math and StringTools are available');
		equals(Script.fromString('function f() return Json.parse("{\\"a\\":5}").a;', 'j').call('f'), 5, 'Json is available');
		check(Script.fromString('function f() return mobile.isMobile;', 'm').call('f') == false, 'the mobile API is available');

		throwsWith(function() Script.fromString('function (', 'broken'), 'broken', 'syntax errors name the script');
		throwsWith(function() Script.fromString('function f() { return missing + 1; }', 'rt').call('f'), 'rt:f', 'runtime errors name the script and function');
		throwsWith(function() Script.fromString('function f() { mobile.impact("gentle"); }', 'api').call('f'), 'Unknown impact style', 'the mobile API validates its arguments');
	}

	static function testSandbox():Void
	{
		throwsWith(function() Script.fromString('function f() return new sys.io.Process("cmd", []);', 'p').call('f'), 'not available to scripts', 'blocks creating arbitrary classes');
		throwsWith(function() Script.fromString('function f() return new haxe.ds.ObjectMap();', 'b').call('f'), 'not available to scripts', 'blocks classes that are not allowed');
		check(Script.fromString('function f() return new StringBuf();', 'sb').call('f') != null, 'allows StringBuf');

		// Reflect, Type, Sys and File are simply not given to scripts.
		for (name in ['Reflect', 'Type', 'Sys', 'File', 'FileSystem'])
			throwsWith(function() Script.fromString('function f() return $name;', 'v').call('f'), 'Unknown variable', '$name is not exposed');

		Script.allowClass('haxe.ds.ObjectMap');
		check(Script.fromString('function f() return new haxe.ds.ObjectMap();', 'bb').call('f') != null, 'allowClass() opens a class up');
	}

	// ---------------------------------------------------------------- file safety

	static function testPathSafety():Void
	{
		var root = FileSystem.fullPath('.') + '/safety/mod';
		write(root + '/inside.txt', 'in');
		write(FileSystem.fullPath('.') + '/safety/secret.txt', 'secret');

		check(ModFiles.resolveInside(root, 'inside.txt') != null, 'a normal file resolves');
		check(ModFiles.resolveInside(root, './sub/../inside.txt') == null, 'rejects ..');
		check(ModFiles.resolveInside(root, '../secret.txt') == null, 'rejects leaving the folder');
		check(ModFiles.resolveInside(root, '..\\secret.txt') == null, 'rejects backslash traversal');
		check(ModFiles.resolveInside(root, '/etc/passwd') == null, 'rejects absolute paths');
		check(ModFiles.resolveInside(root, 'C:/Windows/win.ini') == null, 'rejects drive letters');
		check(ModFiles.resolveInside(root, null) == null, 'rejects null');
	}

	// ---------------------------------------------------------------- mods

	static function testMods():Void
	{
		var base = FileSystem.fullPath('.');
		var root = base + '/modroot';

		// base-pack: no dependencies, logs on load, counts updates, provides a file and a hook.
		write(root + '/base-pack/mod.json', '{"name": "Base Pack", "version": "1.0.0"}');
		write(root + '/base-pack/scripts/main.hx', 'var frames = 0;\nfunction onLoad() { mod.log("base loaded"); }\nfunction onUnload() { mod.log("base unloaded"); }\nfunction onUpdate(dt) { frames++; }\nfunction ping() return "base";');
		write(root + '/base-pack/data/value.txt', 'from base');
		write(root + '/base-pack/data/only-base.txt', 'x');

		// extra: depends on base-pack and overrides a file.
		write(root + '/extra/mod.json', '{"id": "extra", "name": "Extra", "dependencies": ["base-pack"], "scripts": ["scripts/extra.hx"]}');
		write(root + '/extra/scripts/extra.hx', 'function ping() return "extra";\nfunction escape() return [mod.readText("../base-pack/data/value.txt"), mod.readText("/etc/hosts"), mod.exists("../base-pack/mod.json")];');
		write(root + '/extra/data/value.txt', 'from extra');

		// broken: a script with a syntax error must not load.
		write(root + '/broken/mod.json', '{"name": "Broken"}');
		write(root + '/broken/scripts/main.hx', 'function (');

		// thrower: loads fine but throws at runtime.
		write(root + '/thrower/mod.json', '{"name": "Thrower"}');
		write(root + '/thrower/scripts/main.hx', 'function ping() { return nothing.here; }');

		// lonely: needs a mod that does not exist.
		write(root + '/lonely/mod.json', '{"name": "Lonely", "dependencies": ["ghost"]}');

		// circular: a and b need each other.
		write(root + '/circ-a/mod.json', '{"name": "Circ A", "dependencies": ["circ-b"]}');
		write(root + '/circ-b/mod.json', '{"name": "Circ B", "dependencies": ["circ-a"]}');

		// invalid metadata: reported, never listed.
		write(root + '/no-name/mod.json', '{"id": "no-name"}');
		write(root + '/bad-json/mod.json', '{not json');
		write(root + '/bad id/mod.json', '{"name": "Bad", "id": "has space"}');
		write(root + '/not-a-mod/readme.txt', 'no mod.json here');

		var errors:Array<String> = [];
		var logs:Array<String> = [];
		var changes = 0;
		ModManager.onError = function(source, message) errors.push('$source: $message');
		ModManager.onLog = function(source, message) logs.push('$source: $message');
		ModManager.onChanged = function() changes++;
		ModManager.stateFile = base + '/state/mods.json';

		ModManager.addRoot(root);
		ModManager.init();

		var ids = [for (mod in ModManager.mods) mod.id];
		ids.sort(Reflect.compare);
		equals(ids.join(','), 'base-pack,broken,circ-a,circ-b,extra,lonely,thrower', 'finds exactly the valid mods');

		check(errors.filter(e -> e.indexOf('no-name') == 0 && e.indexOf('"name"') >= 0).length == 1, 'reports a missing name');
		check(errors.filter(e -> e.indexOf('bad-json') == 0).length == 1, 'reports invalid JSON');
		check(errors.filter(e -> e.indexOf('bad id') == 0 && e.indexOf('Invalid mod id') >= 0).length == 1, 'reports an invalid id');
		check(errors.filter(e -> e.indexOf('not-a-mod') >= 0).length == 0, 'folders without mod.json are ignored silently');
		check(changes > 0, 'onChanged fires');

		check(ModManager.findFile('data/value.txt') == null, 'nothing is provided while no mod is enabled');

		// Enabling extra pulls in its dependency first.
		check(ModManager.enable('extra'), 'enable() succeeds');
		check(ModManager.isEnabled('base-pack'), 'enabling a mod enables its dependencies');
		check(logs.indexOf('base-pack: base loaded') >= 0, 'onLoad runs and mod.log reaches onLog');

		// Priority: extra comes after base-pack alphabetically? It is sorted by name: "Base Pack" < "Extra".
		equals(ModManager.readText('data/value.txt'), 'from extra', 'the later mod wins a shared file');
		equals(ModManager.readText('data/only-base.txt'), 'x', 'files only one mod has are found');
		equals(ModManager.listFiles('data').join(','), 'only-base.txt,value.txt', 'listFiles merges mods without duplicates');

		ModManager.move('extra', 0);
		equals(ModManager.readText('data/value.txt'), 'from base', 'move() changes which mod wins');
		ModManager.move('extra', 99);
		equals(ModManager.readText('data/value.txt'), 'from extra', 'move() clamps the index');

		// Scripts
		var pings = ModManager.call('ping');
		equals(pings.join(','), 'base,extra', 'call() reaches every enabled mod in order');

		ModManager.update(0.016);
		ModManager.update(0.016);
		equals(ModManager.get('base-pack').scripts[0].get('frames'), 2, 'update() runs onUpdate');

		// A mod cannot read outside its folder.
		var escape:Array<Dynamic> = ModManager.get('extra').scripts[0].call('escape');
		equals(escape[0], null, 'a script cannot read a sibling mod with ..');
		equals(escape[1], null, 'a script cannot read an absolute path');
		equals(escape[2], false, 'exists() refuses to leave the folder');

		// Failures stay contained
		check(!ModManager.enable('broken'), 'a mod with a syntax error does not enable');
		check(ModManager.get('broken').error != null && ModManager.get('broken').error.indexOf('broken/scripts/main.hx') >= 0, 'the error names the script file');
		check(!ModManager.get('broken').enabled && ModManager.get('broken').scripts.length == 0, 'a failed mod stays unloaded');

		check(!ModManager.enable('lonely'), 'a missing dependency blocks enabling');
		check(ModManager.get('lonely').error.indexOf('ghost') >= 0, 'the error names the missing dependency');

		check(!ModManager.enable('circ-a'), 'a circular dependency blocks enabling');
		check(ModManager.get('circ-a').error.indexOf('Circular') >= 0 || ModManager.get('circ-b').error.indexOf('Circular') >= 0, 'the error mentions the cycle');

		errors = [];
		check(ModManager.enable('thrower'), 'a mod whose hook throws still enables');
		var results = ModManager.call('ping');
		equals(results.join(','), 'base,extra', 'a throwing script does not stop the others');
		check(errors.filter(e -> e.indexOf('thrower') == 0).length == 1, 'the throwing script is reported once');

		// Disabling
		logs = [];
		ModManager.disable('base-pack');
		check(!ModManager.isEnabled('base-pack'), 'disable() turns the mod off');
		check(!ModManager.isEnabled('extra'), 'disable() also turns off mods that depend on it');
		check(logs.indexOf('base-pack: base unloaded') >= 0, 'onUnload runs');
		check(ModManager.findFile('data/only-base.txt') == null, 'a disabled mod no longer provides files');

		// Persistence: what is enabled and the order survive a reload.
		ModManager.enable('extra');
		ModManager.move('extra', 0);
		ModManager.disable('thrower');
		ModManager.reload();
		check(ModManager.isEnabled('extra') && ModManager.isEnabled('base-pack'), 'enabled mods are enabled again after reload()');
		check(!ModManager.isEnabled('thrower'), 'disabled mods stay disabled after reload()');
		equals(ModManager.mods[0].id, 'extra', 'the order survives reload()');

		var saved = haxe.Json.parse(ModFiles.readText(base + '/state/mods.json'));
		check((saved.enabled : Array<String>).indexOf('extra') >= 0, 'the state file is written');

		// Exposing a host API
		var scored = 0;
		ModManager.expose('game', {addScore: function(n:Int) scored += n});
		write(root + '/scorer/mod.json', '{"name": "Scorer"}');
		write(root + '/scorer/scripts/main.hx', 'function onLoad() { game.addScore(5); }');
		ModManager.reload();
		check(ModManager.enable('scorer'), 'a mod using an exposed variable enables');
		equals(scored, 5, 'scripts can use what the host exposes');
	}
}
