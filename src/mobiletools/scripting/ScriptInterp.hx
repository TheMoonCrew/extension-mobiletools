package mobiletools.scripting;

import hscript.Expr;
import hscript.Interp;

/**
 * hscript interpreter that only instantiates classes from an allow list.
 *
 * Plain hscript resolves `new Some.Class()` through `Type.resolveClass`, which means a script
 * could create any class compiled into the app (processes, sockets, ...). Everything else a script
 * can reach comes from the variables it is given, so closing this one door is what makes mods safe to load.
 */
class ScriptInterp extends Interp
{
	/** Classes a script may create with `new`, by full name. Add more with `Script.allowClass()`. */
	public static var allowedClasses:Map<String, Bool> = [
		'StringBuf' => true,
		'EReg' => true,
		'Date' => true,
		'haxe.ds.StringMap' => true,
		'haxe.ds.IntMap' => true
	];

	/**
	 * Runs the top level of a script, one statement at a time.
	 *
	 * hscript forgets the `var`s of a block once it ends, which would make a script's own variables
	 * unreachable for `getValue()` and `setValue()`. Running the statements separately keeps them alive.
	 * Declare a `var` before the functions that use it: a function only sees what exists when it is defined.
	 */
	public function executeTopLevel(program:Expr):Void
	{
		depth = 0; // what makes `function` declarations global
		locals = new Map();
		declared = [];

		#if hscriptPos
		var body = program.e;
		#else
		var body = program;
		#end

		switch (body)
		{
			case EBlock(statements):
				for (statement in statements)
					exprReturn(statement);

			default:
				exprReturn(program);
		}
	}

	/**
	 * Reads a variable of the script. A `var` at the top level of a script is a local to hscript,
	 * not a variable, so it has to be looked up separately from what `set()` and functions create.
	 */
	public function getValue(name:String):Dynamic
	{
		var local = locals.get(name);
		return local != null ? local.r : variables.get(name);
	}

	/** Counterpart of `getValue()`: assigns to a top level `var` if there is one, otherwise defines a variable. */
	public function setValue(name:String, value:Dynamic):Void
	{
		var local = locals.get(name);

		if (local != null)
			local.r = value;
		else
			variables.set(name, value);
	}

	/**
	 * hscript's own version catches `break`, `continue` and `return` with `catch (e:Stop)`. On hxcpp (Android, iOS)
	 * that catch also takes any other enum, such as `hscript.Expr.Error` when `hscriptPos` is not defined, and then
	 * returns `null`: a script calling an unknown variable or a blocked class just got `null` instead of an error.
	 * This only handles the real control flow values and rethrows everything else.
	 */
	override function exprReturn(e:Expr):Dynamic
	{
		try
		{
			return expr(e);
		}
		catch (error:Dynamic)
		{
			switch (controlFlow(error))
			{
				case 'SReturn':
					var value = returnValue;
					returnValue = null;
					return value;
				case 'SBreak':
					throw 'Invalid break';
				case 'SContinue':
					throw 'Invalid continue';
				default:
					throw error;
			}
		}
	}

	/** The constructor name when `value` is hscript's private `Stop` enum, otherwise `null`. */
	private static function controlFlow(value:Dynamic):Null<String>
	{
		if (!Reflect.isEnumValue(value))
			return null;

		var constructs = Type.getEnumConstructs(Type.getEnum(value));

		if (constructs.length != 3 || constructs.indexOf('SBreak') < 0 || constructs.indexOf('SContinue') < 0 || constructs.indexOf('SReturn') < 0)
			return null;

		return Type.enumConstructor(value);
	}

	override function cnew(cl:String, args:Array<Dynamic>):Dynamic
	{
		// A class the host handed to the script as a variable.
		var exposed:Dynamic = variables.get(cl);

		if (exposed != null && Std.isOfType(exposed, Class))
			return Type.createInstance(exposed, args);

		if (allowedClasses.exists(cl))
		{
			var type = Type.resolveClass(cl);

			if (type != null)
				return Type.createInstance(type, args);

			return error(ECustom('Cannot create "$cl": it is allowed, but not part of this app. Haxe removes classes nothing uses, so reference it in your code or mark it @:keep'));
		}

		return error(ECustom('Cannot create "$cl": this class is not available to scripts'));
	}
}
