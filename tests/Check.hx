/**
 * Tiny assertion helpers shared by the test programs. Failures are counted and printed, so one run reports everything.
 */
class Check
{
	static var failures:Int = 0;
	static var checks:Int = 0;

	public static function check(condition:Bool, description:String):Void
	{
		checks++;

		if (!condition)
		{
			failures++;
			Sys.println('FAIL: $description');
		}
	}

	public static function equals(actual:Dynamic, expected:Dynamic, description:String):Void
	{
		check(actual == expected, '$description (expected "$expected", got "$actual")');
	}

	public static function throwsWith(action:Void->Void, expectedPart:String, description:String):Void
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

	/** Prints the result and returns the process exit code. */
	public static function finish():Int
	{
		Sys.println(failures == 0 ? 'OK: $checks checks passed' : '$failures of $checks checks FAILED');
		return failures == 0 ? 0 : 1;
	}
}
