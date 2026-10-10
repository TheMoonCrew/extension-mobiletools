package mobiletools.scripting;

import hscript.Parser;
import hscript.Printer;

/**
 * A script written in hscript (Haxe-like syntax, interpreted at runtime).
 *
 * Scripts run in a sandbox: they only see `ScriptApi.defaults()` plus the variables you pass in,
 * and can only create classes on `ScriptInterp.allowedClasses`. There is no execution time limit,
 * so a script with an endless loop will freeze the app.
 *
 * Failures are reported by throwing a `String` that already contains the script name (and the
 * line when your project defines `hscriptPos`).
 *
 * ```haxe
 * var script = Script.fromString('function greet(name) return "Hi " + name;', 'demo');
 * trace(script.call('greet', ['Ana'])); // Hi Ana
 * ```
 */
class Script
{
	/** Name used in error messages, usually the file path. */
	public final name:String;

	private final interp:ScriptInterp;

	private function new(name:String, interp:ScriptInterp)
	{
		this.name = name;
		this.interp = interp;
	}

	/**
	 * Parses and runs the top level of `code`, so its functions and variables become available.
	 *
	 * @param globals Extra variables for the script, on top of `ScriptApi.defaults()`.
	 * @throws String when the code cannot be parsed or fails while running.
	 */
	public static function fromString(code:String, name:String = 'script', ?globals:Map<String, Dynamic>):Script
	{
		var parser = new Parser();
		parser.allowTypes = true;
		parser.allowMetadata = true;
		parser.allowJSON = true;

		var interp = new ScriptInterp();

		for (key => value in ScriptApi.defaults())
			interp.variables.set(key, value);

		if (globals != null)
		{
			for (key => value in globals)
				interp.variables.set(key, value);
		}

		guard(name, function() interp.executeTopLevel(parser.parseString(code, name)));

		return new Script(name, interp);
	}

	/**
	 * Allows scripts to create `className` (full name, e.g. `haxe.ds.ObjectMap`) with `new`.
	 *
	 * The class must be part of your app: Haxe leaves out classes that nothing references, so
	 * mark it `@:keep` (or use it somewhere) or scripts will get an error.
	 */
	public static function allowClass(className:String):Void
	{
		ScriptInterp.allowedClasses.set(className, true);
	}

	/** `true` if the script defines a function called `fn`. */
	public function has(fn:String):Bool
	{
		return Reflect.isFunction(interp.getValue(fn));
	}

	/**
	 * Calls the script's function `fn`. Returns `null` when the script does not define it,
	 * so it is safe to call optional hooks like `onUpdate`.
	 *
	 * @throws String when the function fails.
	 */
	public function call(fn:String, ?args:Array<Dynamic>):Dynamic
	{
		var target:Dynamic = interp.getValue(fn);

		if (!Reflect.isFunction(target))
			return null;

		return guard(name + ':' + fn, function() return Reflect.callMethod(null, target, args != null ? args : []));
	}

	/** Sets a variable the script can read, or assigns to one of its top level `var`s. */
	public function set(variable:String, value:Dynamic):Void
	{
		interp.setValue(variable, value);
	}

	/** Reads a variable (or function) defined by the script, including its top level `var`s. */
	public function get(variable:String):Dynamic
	{
		return interp.getValue(variable);
	}

	/** Runs `action`, turning every kind of failure into a readable `String` throw. */
	private static function guard<T>(where:String, action:Void->T):T
	{
		try
		{
			return action();
		}
		catch (e:hscript.Expr.Error)
		{
			return throw '$where: ' + Printer.errorToString(e);
		}
		catch (e:Dynamic)
		{
			return throw '$where: ' + Std.string(e);
		}
	}
}
