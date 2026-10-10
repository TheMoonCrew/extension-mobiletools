import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;

/**
 * A rounded, tappable button with a pressed state.
 */
class Button extends Sprite
{
	private var buttonWidth:Float;
	private var buttonHeight:Float;
	private var primary:Bool;
	private var pressed:Bool = false;
	private var label:TextField;

	public function new(text:String, width:Float, height:Float, fontSize:Float, onTap:Void->Void, primary:Bool = false)
	{
		super();

		this.buttonWidth = width;
		this.buttonHeight = height;
		this.primary = primary;

		label = Theme.text(text, fontSize, Theme.TEXT, true);
		addChild(label);

		// Children never take the hit, so the whole rectangle is one target.
		mouseChildren = false;
		buttonMode = true;

		addEventListener(MouseEvent.MOUSE_DOWN, onDown);
		addEventListener(MouseEvent.CLICK, function(_) onTap());

		render();
	}

	public function setText(text:String):Void
	{
		label.text = text;
		render();
	}

	/** The primary style marks the main action; other buttons are neutral. */
	public function setPrimary(value:Bool):Void
	{
		primary = value;
		render();
	}

	private function onDown(_):Void
	{
		pressed = true;
		render();

		// The finger may leave the button (or start a scroll) before lifting, so listen on the stage.
		stage.addEventListener(MouseEvent.MOUSE_UP, onRelease);
	}

	private function onRelease(_):Void
	{
		if (stage != null)
			stage.removeEventListener(MouseEvent.MOUSE_UP, onRelease);

		pressed = false;
		render();
	}

	private function render():Void
	{
		var color = primary ? (pressed ? Theme.ACCENT_PRESSED : Theme.ACCENT) : (pressed ? Theme.BUTTON_PRESSED : Theme.BUTTON);

		graphics.clear();
		graphics.beginFill(color);
		graphics.drawRoundRect(0, 0, buttonWidth, buttonHeight, buttonHeight * 0.5, buttonHeight * 0.5);
		graphics.endFill();

		label.x = (buttonWidth - label.width) / 2;
		label.y = (buttonHeight - label.height) / 2;
	}
}
