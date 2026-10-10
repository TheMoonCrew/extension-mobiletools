package mobiletools.mods;

import haxe.Json;
import haxe.io.Bytes;
import mobiletools.mods.ModInfo;
import mobiletools.scripting.Script;

/**
 * A mod found on disk. Get them from `ModManager`.
 *
 * All file functions take paths relative to the mod folder and refuse to leave it,
 * so they are safe to hand to scripts.
 */
class Mod
{
	public final info:ModInfo;

	/** Absolute path of the mod folder. */
	public final path:String;

	/** `true` while the mod's scripts are loaded and its files override the game's. */
	public var enabled(default, null):Bool = false;

	/** Why the mod could not be enabled, or `null`. Cleared by the next successful enable. */
	public var error(default, null):Null<String>;

	/** Scripts loaded while enabled, in run order. */
	public var scripts(default, null):Array<Script> = [];

	public var id(get, never):String;
	public var name(get, never):String;

	@:allow(mobiletools.mods.ModManager)
	private function new(info:ModInfo, path:String)
	{
		this.info = info;
		this.path = path;
	}

	/** Absolute path of `relative` inside this mod, or `null` if it is invalid or does not exist. */
	public function resolve(relative:String):Null<String>
	{
		var full = ModFiles.resolveInside(path, relative);
		return (full != null && ModFiles.isFile(full)) ? full : null;
	}

	public function exists(relative:String):Bool
	{
		return resolve(relative) != null;
	}

	public function readText(relative:String):Null<String>
	{
		var full = resolve(relative);
		return full != null ? ModFiles.readText(full) : null;
	}

	public function readBytes(relative:String):Null<Bytes>
	{
		var full = resolve(relative);
		return full != null ? ModFiles.readBytes(full) : null;
	}

	/** Parses a JSON file of the mod. Returns `null` when it is missing or not valid JSON. */
	public function readJson(relative:String):Dynamic
	{
		var text = readText(relative);

		if (text == null)
			return null;

		try
		{
			return Json.parse(text);
		}
		catch (e:Dynamic)
		{
			return null;
		}
	}

	/** Names of the files (not folders) directly inside the folder `relative`, sorted. */
	public function list(relative:String):Array<String>
	{
		var full = ModFiles.resolveInside(path, relative);

		if (full == null || !ModFiles.isDirectory(full))
			return [];

		return [for (entry in ModFiles.readDirectory(full)) if (ModFiles.isFile(full + '/' + entry)) entry];
	}

	@:allow(mobiletools.mods.ModManager)
	private function setEnabled(value:Bool):Void
	{
		enabled = value;
	}

	@:allow(mobiletools.mods.ModManager)
	private function setError(value:Null<String>):Void
	{
		error = value;
	}

	@:allow(mobiletools.mods.ModManager)
	private function setScripts(value:Array<Script>):Void
	{
		scripts = value;
	}

	private inline function get_id():String
	{
		return info.id;
	}

	private inline function get_name():String
	{
		return info.name;
	}
}
