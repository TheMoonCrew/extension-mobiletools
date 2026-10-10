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
 *     "scripts": ["scripts/main.hx"]
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
			scripts: stringArrayField(data, 'scripts')
		};
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
