import lime.app.Application;
import lime.ui.MouseButton;
import mobiletools.MobileTools;
import mobiletools.Permissions;

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
		trace('Camera permission: ${Permissions.check(CAMERA)}');

		MobileTools.setKeepScreenOn(true);
	}

	// Tap / click anywhere to trigger the demo calls.
	override public function onMouseDown(x:Float, y:Float, button:MouseButton):Void
	{
		MobileTools.vibrate(80);

		Permissions.request(CAMERA, function(status)
		{
			MobileTools.showToast('Camera permission: $status');

			// Once the user chose "don't ask again" only the system settings can change it.
			if (status == DENIED_PERMANENTLY)
				Permissions.openSettings();
		});
	}
}
