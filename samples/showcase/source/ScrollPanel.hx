import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.geom.Rectangle;

/**
 * A vertically scrolling viewport with touch dragging, momentum and mouse wheel support.
 *
 * Add your content to `content` and call `setContentHeight()` once it is laid out.
 */
class ScrollPanel extends Sprite
{
	/** Drag distance after which a touch becomes a scroll instead of a tap. */
	private var dragThreshold:Float;

	/** Fraction of the speed kept every frame while coasting. */
	private static inline var FRICTION:Float = 0.95;

	public var content(default, null):Sprite = new Sprite();

	/** How far the content is scrolled down, in pixels. 0 is the top. */
	public var scrollPosition(get, set):Float;

	private var viewHeight:Float;
	private var contentHeight:Float = 0;

	private var tracking:Bool = false;
	private var dragging:Bool = false;
	private var pointerStart:Float = 0;
	private var contentStart:Float = 0;
	private var lastPointer:Float = 0;
	private var lastMoveTime:Int = 0;
	private var velocity:Float = 0;

	public function new(width:Float, height:Float, dragThreshold:Float)
	{
		super();

		this.viewHeight = height;
		this.dragThreshold = dragThreshold;

		scrollRect = new Rectangle(0, 0, width, height);
		addChild(content);

		addEventListener(MouseEvent.MOUSE_DOWN, onDown);
		addEventListener(Event.ADDED_TO_STAGE, function(_) stage.addEventListener(MouseEvent.MOUSE_WHEEL, onWheel));
		addEventListener(Event.REMOVED_FROM_STAGE, function(_) stage.removeEventListener(MouseEvent.MOUSE_WHEEL, onWheel));
	}

	public function setContentHeight(value:Float):Void
	{
		contentHeight = value;
		content.y = clamp(content.y);
	}

	private function onDown(_):Void
	{
		velocity = 0;
		tracking = true;
		dragging = false;
		pointerStart = lastPointer = stage.mouseY;

		stage.addEventListener(MouseEvent.MOUSE_MOVE, onMove);
		stage.addEventListener(MouseEvent.MOUSE_UP, onUp);
		addEventListener(Event.ENTER_FRAME, step);
	}

	private function onMove(_):Void
	{
		if (!tracking)
			return;

		var pointer = stage.mouseY;

		if (!dragging && Math.abs(pointer - pointerStart) > dragThreshold)
		{
			dragging = true;
			pointerStart = pointer;
			contentStart = content.y;

			// From now on this is a scroll, so stop the buttons underneath from receiving the tap.
			content.mouseChildren = false;
		}

		if (dragging)
		{
			velocity = pointer - lastPointer;
			content.y = clamp(contentStart + pointer - pointerStart);
		}

		lastPointer = pointer;
		lastMoveTime = Lib.getTimer();
	}

	private function onUp(_):Void
	{
		stage.removeEventListener(MouseEvent.MOUSE_MOVE, onMove);
		stage.removeEventListener(MouseEvent.MOUSE_UP, onUp);

		tracking = false;

		// A finger that rested before lifting should not fling.
		if (Lib.getTimer() - lastMoveTime > 80)
			velocity = 0;
	}

	private function step(_):Void
	{
		if (tracking)
			return;

		// Re-enable taps one frame after the release, once the click has been decided.
		content.mouseChildren = true;
		dragging = false;

		if (Math.abs(velocity) > 0.5)
		{
			var target = content.y + velocity;
			content.y = clamp(target);
			velocity = (content.y == target) ? velocity * FRICTION : 0;
		}
		else
		{
			velocity = 0;
			removeEventListener(Event.ENTER_FRAME, step);
		}
	}

	private function onWheel(e:MouseEvent):Void
	{
		content.y = clamp(content.y + e.delta * 20);
	}

	private function get_scrollPosition():Float
	{
		return -content.y;
	}

	private function set_scrollPosition(value:Float):Float
	{
		content.y = clamp(-value);
		return value;
	}

	private function clamp(y:Float):Float
	{
		return Math.max(Math.min(0, viewHeight - contentHeight), Math.min(0, y));
	}
}
