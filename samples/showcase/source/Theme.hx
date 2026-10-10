import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;

/**
 * Colors and text helpers shared by the showcase UI.
 */
class Theme
{
	public static inline var BACKGROUND:Int = 0x0F1318;
	public static inline var CARD:Int = 0x1A2028;
	public static inline var BUTTON:Int = 0x2A3441;
	public static inline var BUTTON_PRESSED:Int = 0x394658;
	public static inline var ACCENT:Int = 0x4F8CFF;
	public static inline var ACCENT_PRESSED:Int = 0x3A6FD0;
	public static inline var TEXT:Int = 0xE8ECF1;
	public static inline var MUTED:Int = 0x8A95A3;
	public static inline var OK:Int = 0x3DDC84;
	public static inline var WARN:Int = 0xF5B642;
	public static inline var BAD:Int = 0xFF5C5C;

	/** Shortens `value` to at most `max` characters, ending in an ellipsis. */
	public static function clip(value:String, max:Int):String
	{
		return value.length <= max ? value : value.substr(0, max - 1) + "...";
	}

	/**
	 * Creates a non-interactive label.
	 *
	 * @param width wraps the text to this width when greater than 0.
	 */
	public static function text(value:String, size:Float, color:Int = TEXT, bold:Bool = false, width:Float = 0):TextField
	{
		var field = new TextField();
		field.defaultTextFormat = new TextFormat('_sans', Std.int(size), color, bold);
		field.selectable = false;
		field.mouseEnabled = false;
		field.autoSize = TextFieldAutoSize.LEFT;

		if (width > 0)
		{
			field.multiline = true;
			field.wordWrap = true;
			field.width = width;
		}

		field.text = value;
		return field;
	}
}
