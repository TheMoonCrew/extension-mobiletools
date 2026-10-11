package mobiletools.mods;

import haxe.Json;

/**
 * The contents of a mod's `mod.json`.
 *
 * ```json
 * {
 *     "id": "cool-colors",
 *     "name": "Cool Colors",
 *     "version": "1.0.0",
 *     "author": "Ana",
 *     "description": "Changes the palette.",
 *     "dependencies": ["base-pack"],
 *     "scripts": ["scripts/main.hx"],
 *     "platforms": ["android", "ios"]
 * }
 * ```
 *
 * Only `name` is required. `id` defaults to the folder name.
 */
typedef ModInfo =
{
	/** Unique identifier. Letters, digits, `-`, `_` and `.`. */
	var id:String;

	/** Name shown to the user. */
	var name:String;

	@:optional var version:String;
	@:optional var author:String;
	@:optional var description:String;

	/** Ids of mods that are enabled together with this one. */
	@:optional var dependencies:Array<String>;

	/** Script files, relative to the mod folder, run in this order. Defaults to everything in `scripts/`. */
	@:optional var scripts:Array<String>;

	/**
	 * Where the mod can be enabled: any of `android`, `ios`, `mobile` (both), `desktop` and `html5`.
	 * Everywhere when missing. On other platforms the mod is still listed, with `Mod.error` explaining why it is off.
	 */
	@:optional var platforms:Array<String>;
}

class ModInfoTools
{
	/**
	 * Parses and validates a `mod.json`.
	 *
	 * @param folderName Used as the id when the file does not set one.
	 * @throws String describing what is wrong.
	 */
	public static function parse(json:String, folderName:String):ModInfo
	{
		var data:Dynamic;

		try
		{
			data = Json.parse(json);
		}
		catch (e:Dynamic)
		{
			throw 'mod.json is not valid JSON: ' + Std.string(e);
		}

		if (data == null || Type.typeof(data) != TObject)
			throw 'mod.json must contain a JSON object';

		var id:String = stringField(data, 'id', folderName);
		var name:String = stringField(data, 'name', null);

		if (name == null || StringTools.trim(name) == '')
			throw 'mod.json needs a "name"';

		if (!~/^[A-Za-z0-9_.\-]+$/.match(id))
			throw 'Invalid mod id "$id": use only letters, digits, "-", "_" and "."';

		return {
			id: id,
			name: name,
			version: stringField(data, 'version', null),
			author: stringField(data, 'author', null),
			description: stringField(data, 'description', null),
			dependencies: stringArrayField(data, 'dependencies'),
			scripts: stringArrayField(data, 'scripts'),
			platforms: stringArrayField(data, 'platforms')
		};
	}

	/** The name `platforms` uses for the platform this runs on. */
	public static function currentPlatform():String
	{
		#if android
		return 'android';
		#elseif ios
		return 'ios';
		#elseif (js && html5)
		return 'html5';
		#else
		return 'desktop';
		#end
	}

	/** `true` when `platforms` is missing or names `platform` (with `mobile` covering both phones). */
	public static function supports(info:ModInfo, platform:String):Bool
	{
		if (info.platforms == null)
			return true;

		for (name in info.platforms)
		{
			var clean = name.toLowerCase();

			if (clean == platform || (clean == 'mobile' && (platform == 'android' || platform == 'ios')))
				return true;
		}

		return false;
	}

	private static function stringField(data:Dynamic, field:String, fallback:Null<String>):Null<String>
	{
		var value:Dynamic = Reflect.field(data, field);

		if (value == null)
			return fallback;

		if (!Std.isOfType(value, String))
			throw '"$field" in mod.json must be a string';

		return value;
	}

	private static function stringArrayField(data:Dynamic, field:String):Null<Array<String>>
	{
		var value:Dynamic = Reflect.field(data, field);

		if (value == null)
			return null;

		if (!Std.isOfType(value, Array))
			throw '"$field" in mod.json must be a list of strings';

		var result:Array<String> = [];

		for (item in (value : Array<Dynamic>))
		{
			if (!Std.isOfType(item, String))
				throw '"$field" in mod.json must be a list of strings';

			result.push(item);
		}

		return result;
	}
}
