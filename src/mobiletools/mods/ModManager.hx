package mobiletools.mods;

import haxe.Json;
import haxe.io.Bytes;
import haxe.io.Path;
import mobiletools.HapticLibrary;
import mobiletools.HapticPattern;
import mobiletools.MobileTools;
import mobiletools.Permissions;
import mobiletools.StorageDirectory;
import mobiletools.mods.ModInfo;
import mobiletools.scripting.Script;
import mobiletools.scripting.ScriptApi;

/**
 * Finds, enables and runs mods.
 *
 * A mod is a folder with a `mod.json` (see `ModInfo`), optional scripts in `scripts/`, and any files that
 * should replace or add to the game's own. The folder is looked for in every root, which are
 * `<app external folder>/mods` by default plus whatever you add with `addRoot()` or `useSharedStorage()`.
 *
 * ```haxe
 * ModManager.init();
 * ModManager.onLog = (source, message) -> trace('[$source] $message');
 *
 * for (mod in ModManager.mods)
 *     trace(mod.name);
 *
 * ModManager.enable('cool-colors');
 * var background = ModManager.findFile('images/bg.png'); // the mod's file, or null
 *
 * // each frame:
 * ModManager.update(elapsed);
 * ```
 *
 * Order matters: mods later in `mods` win when several provide the same file. Change it with `move()`.
 * Which mods are enabled, and their order, is remembered between launches.
 *
 * Nothing here runs on html5 (no file system): there are simply no mods.
 */
class ModManager
{
	/** Name of the folder, inside each root, that holds the mods. */
	public static inline var MODS_FOLDER:String = 'mods';

	/** Where the enabled mods and their order are saved. Defaults to a file in the internal app folder. */
	public static var stateFile:String;

	/** Called when a mod fails to load or one of its scripts throws. `source` is a mod id or folder. */
	public static var onError:(source:String, message:String) -> Void = function(source, message) trace('[mods] $source: $message');

	/** Called when a script writes with `mod.log()`. */
	public static var onLog:(source:String, message:String) -> Void = function(source, message) trace('[$source] $message');

	/** Called after mods were found again, enabled, disabled or reordered. */
	public static var onChanged:() -> Void;

	/** Every mod found, in priority order (later wins). A copy: use the functions below to change things. */
	public static var mods(get, never):Array<Mod>;

	private static var list:Array<Mod> = [];
	private static var roots:Array<String> = [];
	private static var globals:Map<String, Dynamic> = new Map();
	private static var enabledIds:Array<String> = [];
	private static var order:Array<String> = [];
	private static var initialized:Bool = false;

	/**
	 * Prepares the manager: adds the app's own mods folder, restores the saved state and scans for mods.
	 * Safe to call more than once.
	 */
	public static function init():Void
	{
		if (initialized)
			return;

		initialized = true;

		if (stateFile == null)
		{
			var internal = MobileTools.getDirectory(INTERNAL);

			if (internal != '')
				stateFile = Path.join([internal, 'mobiletools_mods.json']);
		}

		loadState();

		var appFolder = MobileTools.getDirectory(APP_EXTERNAL);

		if (appFolder != '')
		{
			var root = Path.join([appFolder, MODS_FOLDER]);
			ModFiles.ensureDirectory(root);
			addRoot(root, false);
		}

		reload();
	}

	/** Also looks for mods in `path`. Call `reload()` afterwards (unless you are before `init()`). */
	public static function addRoot(path:String, rescan:Bool = true):Void
	{
		var clean = Path.removeTrailingSlashes(path);

		if (clean == '' || roots.indexOf(clean) >= 0)
			return;

		roots.push(clean);

		if (rescan && initialized)
			reload();
	}

	/** Stops looking for mods in `path`. Mods already found there are dropped on the next `reload()`. */
	public static function removeRoot(path:String):Void
	{
		roots.remove(Path.removeTrailingSlashes(path));
	}

	/** The folders mods are searched in. */
	public static function getRoots():Array<String>
	{
		return roots.copy();
	}

	/**
	 * Also looks for mods in `<shared storage>/<folder>/mods`, the place users can reach from a file
	 * manager or their computer. This asks for `Permission.EXTERNAL_STORAGE` first (see its notes).
	 *
	 * @param callback `true` when the folder is being used, `false` if the permission was refused or there is no shared storage.
	 */
	public static function useSharedStorage(folder:String, ?callback:Bool->Void):Void
	{
		if (folder == null || folder == '' || folder.indexOf('/') >= 0 || folder.indexOf('\\') >= 0 || folder.indexOf('..') >= 0)
		{
			report(folder, 'Invalid shared storage folder name');

			if (callback != null)
				callback(false);

			return;
		}

		Permissions.request(EXTERNAL_STORAGE, function(status)
		{
			var base = MobileTools.getDirectory(SHARED);
			var usable = status.isGranted() && base != '';

			if (usable)
			{
				var root = Path.join([base, folder, MODS_FOLDER]);
				usable = ModFiles.ensureDirectory(root);

				if (usable)
					addRoot(root);
			}

			if (callback != null)
				callback(usable);
		});
	}

	/** Scans every root again. Mods that were enabled and still exist are enabled again. */
	public static function reload():Void
	{
		init();

		// Remember what the user had on before throwing everything away.
		var wasEnabled = [for (mod in list) if (mod.enabled) mod.id];

		for (mod in list.copy())
			unload(mod);

		list = [];

		for (root in roots)
			scan(root);

		sortByOrder();

		for (mod in list)
		{
			if (!mod.enabled && (enabledIds.indexOf(mod.id) >= 0 || wasEnabled.indexOf(mod.id) >= 0))
				enableMod(mod, []);
		}

		saveState();
		changed();
	}

	public static function get(id:String):Null<Mod>
	{
		for (mod in list)
		{
			if (mod.id == id)
				return mod;
		}

		return null;
	}

	/**
	 * Enables a mod, after enabling the mods it depends on. Loads its scripts and calls their `onLoad()`.
	 *
	 * @return `false` if it does not exist or failed to load, see `Mod.error`.
	 */
	public static function enable(id:String):Bool
	{
		init();

		var mod = get(id);

		if (mod == null)
			return false;

		var success = enableMod(mod, []);

		saveState();
		changed();
		return success;
	}

	/** Disables a mod, and any enabled mod that depends on it. Calls `onUnload()` in its scripts. */
	public static function disable(id:String):Void
	{
		var mod = get(id);

		if (mod == null || !mod.enabled)
			return;

		for (other in list)
		{
			if (other.enabled && other.info.dependencies != null && other.info.dependencies.indexOf(id) >= 0)
				disable(other.id);
		}

		unload(mod);
		saveState();
		changed();
	}

	public static function isEnabled(id:String):Bool
	{
		var mod = get(id);
		return mod != null && mod.enabled;
	}

	/** Moves a mod to `index` in `mods`. Later mods win when several provide the same file. */
	public static function move(id:String, index:Int):Void
	{
		var mod = get(id);

		if (mod == null)
			return;

		list.remove(mod);
		list.insert(Std.int(Math.max(0, Math.min(index, list.length))), mod);

		order = [for (m in list) m.id];
		saveState();
		changed();
	}

	// ---------------------------------------------------------------- files

	/** Absolute path of `path` in the highest priority enabled mod that has it, or `null`. */
	public static function findFile(path:String):Null<String>
	{
		var i = list.length;

		while (i-- > 0)
		{
			if (list[i].enabled)
			{
				var found = list[i].resolve(path);

				if (found != null)
					return found;
			}
		}

		return null;
	}

	/** Text of `path` from the highest priority enabled mod that has it, or `null`. */
	public static function readText(path:String):Null<String>
	{
		var found = findFile(path);
		return found != null ? ModFiles.readText(found) : null;
	}

	/** Bytes of `path` from the highest priority enabled mod that has it, or `null`. */
	public static function readBytes(path:String):Null<Bytes>
	{
		var found = findFile(path);
		return found != null ? ModFiles.readBytes(found) : null;
	}

	/** File names inside the folder `path`, merged from every enabled mod, without duplicates and sorted. */
	public static function listFiles(path:String):Array<String>
	{
		var names:Map<String, Bool> = new Map();

		for (mod in list)
		{
			if (mod.enabled)
			{
				for (name in mod.list(path))
					names.set(name, true);
			}
		}

		var result = [for (name in names.keys()) name];
		result.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		return result;
	}

	// ---------------------------------------------------------------- scripting

	/**
	 * Makes `value` available to every script as the variable `name`. This is how your game gives mods
	 * something to work with. Only expose what a mod should be allowed to do.
	 * Scripts that are already loaded do not see it until the mod is enabled again.
	 */
	public static function expose(name:String, value:Dynamic):Void
	{
		globals.set(name, value);
	}

	/**
	 * Allows scripts to create `className` (full name) with `new`. Off by default for everything but a few basics.
	 * The class has to be compiled into your app, see `Script.allowClass()`.
	 */
	public static function allowClass(className:String):Void
	{
		Script.allowClass(className);
	}

	/**
	 * Calls the function `fn` in the scripts of every enabled mod, in mod order. A script that throws is
	 * reported to `onError` and skipped, the others still run.
	 *
	 * @return what each script that defines `fn` returned.
	 */
	public static function call(fn:String, ?args:Array<Dynamic>):Array<Dynamic>
	{
		var results:Array<Dynamic> = [];

		for (mod in list)
		{
			if (mod.enabled)
				results = results.concat(callMod(mod, fn, args));
		}

		return results;
	}

	/** Shortcut for `call('onUpdate', [elapsed])`: put it in your game loop. */
	public static function update(elapsed:Float):Void
	{
		call('onUpdate', [elapsed]);
	}

	// ---------------------------------------------------------------- internals

	private static function get_mods():Array<Mod>
	{
		return list.copy();
	}

	private static function scan(root:String):Void
	{
		for (entry in ModFiles.readDirectory(root))
		{
			var folder = Path.join([root, entry]);
			var infoFile = Path.join([folder, 'mod.json']);

			if (!ModFiles.isDirectory(folder) || !ModFiles.isFile(infoFile))
				continue;

			try
			{
				var info = ModInfoTools.parse(ModFiles.readText(infoFile), entry);

				if (get(info.id) != null)
					throw 'Another mod already uses the id "${info.id}"';

				list.push(new Mod(info, folder));
			}
			catch (e:Dynamic)
			{
				report(entry, Std.string(e));
			}
		}
	}

	/** Puts mods in the saved order, with new ones last in alphabetical order. */
	private static function sortByOrder():Void
	{
		var position = function(mod:Mod):Int
		{
			var index = order.indexOf(mod.id);
			return index >= 0 ? index : order.length;
		};

		list.sort(function(a, b)
		{
			var difference = position(a) - position(b);

			if (difference != 0)
				return difference;

			return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
		});

		order = [for (mod in list) mod.id];
	}

	private static function enableMod(mod:Mod, chain:Array<String>):Bool
	{
		if (mod.enabled)
			return true;

		if (chain.indexOf(mod.id) >= 0)
			return fail(mod, 'Circular dependency: ' + chain.concat([mod.id]).join(' -> '));

		chain.push(mod.id);

		for (dependency in (mod.info.dependencies != null ? mod.info.dependencies : []))
		{
			var required = get(dependency);

			if (required == null)
				return fail(mod, 'Needs the mod "$dependency", which was not found');

			if (!enableMod(required, chain))
				return fail(mod, 'Needs the mod "$dependency", which could not be enabled: ' + required.error);
		}

		// Before the scripts run, so patterns they save with haptics.define() while loading are kept.
		mod.setHaptics(loadHaptics(mod));

		// All or nothing: a half-loaded mod is worse than a disabled one.
		var loaded:Array<Script> = [];

		for (file in scriptFiles(mod))
		{
			var code = mod.readText(file);

			if (code == null)
				return fail(mod, 'Script "$file" could not be read');

			try
			{
				loaded.push(Script.fromString(code, mod.id + '/' + file, scriptGlobals(mod)));
			}
			catch (e:Dynamic)
			{
				return fail(mod, Std.string(e));
			}
		}

		mod.setScripts(loaded);
		mod.setError(null);
		mod.setEnabled(true);

		callMod(mod, 'onLoad');
		return true;
	}

	private static function unload(mod:Mod):Void
	{
		if (mod.enabled)
			callMod(mod, 'onUnload');

		mod.setScripts([]);
		mod.setHaptics(new Map());
		mod.setEnabled(false);
	}

	private static function callMod(mod:Mod, fn:String, ?args:Array<Dynamic>):Array<Dynamic>
	{
		var results:Array<Dynamic> = [];

		for (script in mod.scripts)
		{
			if (!script.has(fn))
				continue;

			try
			{
				results.push(script.call(fn, args));
			}
			catch (e:Dynamic)
			{
				report(mod.id, Std.string(e));
			}
		}

		return results;
	}

	private static function scriptFiles(mod:Mod):Array<String>
	{
		if (mod.info.scripts != null)
			return mod.info.scripts;

		return [for (name in mod.list('scripts')) if (StringTools.endsWith(name, '.hx') || StringTools.endsWith(name, '.hscript')) 'scripts/' + name];
	}

	/** What the scripts of `mod` can see: the shared variables plus a `mod` object limited to its own folder. */
	private static function scriptGlobals(mod:Mod):Map<String, Dynamic>
	{
		var variables:Map<String, Dynamic> = new Map();

		for (key => value in globals)
			variables.set(key, value);

		// Patterns a script saves belong to its mod, so disabling the mod takes them away again.
		variables.set('haptics', ScriptApi.createHapticsApi(function(name, pattern)
		{
			mod.scriptHaptics.set(name, pattern);
			syncHaptics();
		}));

		variables.set('mod', {
			id: mod.id,
			name: mod.name,
			version: mod.info.version,
			log: function(message:Dynamic):Void
			{
				if (onLog != null)
					onLog(mod.id, Std.string(message));
			},
			exists: function(file:String):Bool return mod.exists(file),
			readText: function(file:String):Null<String> return mod.readText(file),
			readJson: function(file:String):Dynamic return mod.readJson(file),
			list: function(folder:String):Array<String> return mod.list(folder)
		});

		return variables;
	}

	/**
	 * Reads every `haptics/*.json` of the mod. A pattern is named by its `name` field, or else by the file name.
	 * A broken file is reported and skipped, it doesn't stop the mod from loading.
	 */
	private static function loadHaptics(mod:Mod):Map<String, HapticPattern>
	{
		var patterns:Map<String, HapticPattern> = new Map();

		for (file in mod.list('haptics'))
		{
			if (!StringTools.endsWith(file.toLowerCase(), '.json'))
				continue;

			try
			{
				var pattern = HapticPattern.fromJson(mod.readText('haptics/' + file));

				// A name inside the file wins over the file name.
				if (pattern.name == null)
					pattern.name = Path.withoutExtension(file);

				patterns.set(pattern.name, pattern);
			}
			catch (e:Dynamic)
			{
				report(mod.id, 'haptics/' + file + ': ' + Std.string(e));
			}
		}

		return patterns;
	}

	/**
	 * Publishes the haptic patterns of every enabled mod to `HapticLibrary`, so `Haptics.playNamed()` and scripts find
	 * them. Later mods win, and all of them win over the app's own patterns and the built in ones.
	 */
	private static function syncHaptics():Void
	{
		HapticLibrary.removeLayersWithPrefix('mod:');

		for (i in 0...list.length)
		{
			var mod = list[i];

			if (!mod.enabled)
				continue;

			var patterns:Map<String, HapticPattern> = new Map();

			for (name => pattern in mod.haptics)
				patterns.set(name, pattern);

			for (name => pattern in mod.scriptHaptics)
				patterns.set(name, pattern);

			if (patterns.keys().hasNext())
				HapticLibrary.setLayer('mod:' + mod.id, HapticLibrary.PRIORITY_MODS + i, patterns);
		}
	}

	private static function fail(mod:Mod, message:String):Bool
	{
		mod.setHaptics(new Map());
		mod.setError(message);
		report(mod.id, message);
		return false;
	}

	private static function report(source:String, message:String):Void
	{
		if (onError != null)
			onError(source, message);
	}

	private static function changed():Void
	{
		syncHaptics();

		if (onChanged != null)
			onChanged();
	}

	private static function loadState():Void
	{
		if (stateFile == null)
			return;

		var text = ModFiles.readText(stateFile);

		if (text == null)
			return;

		try
		{
			var state:Dynamic = Json.parse(text);
			enabledIds = stringList(state.enabled);
			order = stringList(state.order);
		}
		catch (e:Dynamic)
		{
			// A damaged state file only loses the user's choices, it must never stop the game.
			report('state', 'Ignoring unreadable state file: ' + Std.string(e));
		}
	}

	private static function saveState():Void
	{
		enabledIds = [for (mod in list) if (mod.enabled) mod.id];

		if (stateFile == null)
			return;

		ModFiles.ensureDirectory(Path.directory(stateFile));
		ModFiles.writeText(stateFile, Json.stringify({enabled: enabledIds, order: [for (mod in list) mod.id]}, null, '  '));
	}

	private static function stringList(value:Dynamic):Array<String>
	{
		if (value == null || !Std.isOfType(value, Array))
			return [];

		return [for (item in (value : Array<Dynamic>)) if (Std.isOfType(item, String)) (item : String)];
	}
}
