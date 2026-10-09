import lime.app.Application;
import lime.ui.MouseButton;
import mobiletools.MobileTools;

class Main extends Application
{
	public function new()
	{
		super();
	}

	override public function onWindowCreate():Void
	{
		var info = MobileTools.getDeviceInfo();
		trace('Mobile: ${MobileTools.isMobile}, native backend: ${MobileTools.isSupported}');
		trace('${info.manufacturer} ${info.model} (OS ${info.osVersion}, API ${info.apiLevel})');

		MobileTools.setKeepScreenOn(true);
	}

	// Tap / click anywhere to trigger the demo calls.
	override public function onMouseDown(x:Float, y:Float, button:MouseButton):Void
	{
		MobileTools.showToast('Hello from extension-mobiletools!');
		MobileTools.vibrate(80);
	}
}
