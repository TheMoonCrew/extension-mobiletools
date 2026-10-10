package mobiletools.mods;

import haxe.io.Bytes;
import haxe.io.Path;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * File access used by the mod system. Every function is safe to call on targets without a file
 * system (html5): reads return `null` / empty and writes return `false`.
 */
@:noCompletion
class ModFiles
{
	public static function isDirectory(path:String):Bool
	{
		#if sys
		return FileSystem.exists(path) && FileSystem.isDirectory(path);
		#else
		return false;
		#end
	}

	public static function isFile(path:String):Bool
	{
		#if sys
		return FileSystem.exists(path) && !FileSystem.isDirectory(path);
		#else
		return false;
		#end
	}

	/** Entry names (not paths) in `path`, sorted. Empty when it cannot be read. */
	public static function readDirectory(path:String):Array<String>
	{
		#if sys
		try
		{
			var entries = FileSystem.readDirectory(path);
			entries.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
			return entries;
		}
		catch (e:Dynamic) {}
		#end

		return [];
	}

	public static function readText(path:String):Null<String>
	{
		#if sys
		try
		{
			return File.getContent(path);
		}
		catch (e:Dynamic) {}
		#end

		return null;
	}

	public static function readBytes(path:String):Null<Bytes>
	{
		#if sys
		try
		{
			return File.getBytes(path);
		}
		catch (e:Dynamic) {}
		#end

		return null;
	}

	public static function writeText(path:String, content:String):Bool
	{
		#if sys
		try
		{
			File.saveContent(path, content);
			return true;
		}
		catch (e:Dynamic) {}
		#end

		return false;
	}

	/** Creates `path` and any missing parent folders. */
	public static function ensureDirectory(path:String):Bool
	{
		#if sys
		if (isDirectory(path))
			return true;

		var parent = Path.directory(path);

		if (parent != '' && parent != path)
			ensureDirectory(parent);

		try
		{
			FileSystem.createDirectory(path);
		}
		catch (e:Dynamic) {}

		return isDirectory(path);
		#else
		return false;
		#end
	}

	/**
	 * Joins `relative` onto `root`, or returns `null` if it would leave `root`.
	 *
	 * This is what keeps a mod (and its scripts) inside its own folder: absolute paths, drive letters,
	 * `..` segments and symbolic links pointing elsewhere are all rejected.
	 */
	public static function resolveInside(root:String, relative:String):Null<String>
	{
		if (relative == null)
			return null;

		var clean = relative.split('\\').join('/');

		if (clean.indexOf(':') >= 0 || clean.indexOf(String.fromCharCode(0)) >= 0 || clean.charAt(0) == '/')
			return null;

		var parts:Array<String> = [];

		for (part in clean.split('/'))
		{
			if (part == '' || part == '.')
				continue;

			if (part == '..')
				return null;

			parts.push(part);
		}

		var full = Path.join([root].concat(parts));

		#if sys
		// Follow symbolic links: a mod must not be able to point a file at something outside its folder.
		if (FileSystem.exists(full))
		{
			var realRoot = normalize(FileSystem.fullPath(root));
			var realFull = normalize(FileSystem.fullPath(full));

			if (realFull != realRoot && !StringTools.startsWith(realFull, realRoot + '/'))
				return null;
		}
		#end

		return full;
	}

	private static function normalize(path:String):String
	{
		return Path.removeTrailingSlashes(path.split('\\').join('/'));
	}
}
