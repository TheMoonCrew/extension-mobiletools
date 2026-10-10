import mobiletools.DeviceInfo;
import mobiletools.Haptics;
import mobiletools.MobileTools;
import mobiletools.Permission;
import mobiletools.PermissionStatus;
import mobiletools.Permissions;
import openfl.display.Sprite;
import openfl.display.StageAlign;
import openfl.display.StageScaleMode;
import openfl.events.Event;
import openfl.text.TextField;

/**
 * Touch-friendly demo of every extension-mobiletools feature.
 *
 * Everything is laid out in units of `u` (1 unit = 1 px on a 360 px wide screen), so the same
 * code looks right on a small phone, a tablet and the desktop preview window.
 */
class Main extends Sprite
{
	private var u:Float = 1;
	private var panel:ScrollPanel;
	private var statusText:TextField;
	private var rows:Array<PermissionRow> = [];
	private var keepScreenOn:Bool = false;

	public function new()
	{
		super();
		addEventListener(Event.ADDED_TO_STAGE, onAddedToStage);
	}

	private function onAddedToStage(_):Void
	{
		removeEventListener(Event.ADDED_TO_STAGE, onAddedToStage);

		stage.scaleMode = StageScaleMode.NO_SCALE;
		stage.align = StageAlign.TOP_LEFT;

		stage.addEventListener(Event.RESIZE, function(_) build());

		// Coming back from the system settings (or a permission dialog) may have changed a status.
		stage.addEventListener(Event.ACTIVATE, function(_) refreshAll());

		build();
	}

	private function build():Void
	{
		removeChildren();
		rows = [];

		var width = stage.stageWidth;
		var height = stage.stageHeight;

		if (width <= 0 || height <= 0)
			return;

		u = Math.max(0.5, width / 360);

		var pad = 16 * u;
		var barHeight = 44 * u;
		var contentWidth = width - pad * 2;

		graphics.clear();
		graphics.beginFill(Theme.BACKGROUND);
		graphics.drawRect(0, 0, width, height);
		graphics.endFill();

		panel = new ScrollPanel(width, height - barHeight, 10 * u);
		addChild(panel);

		var y = pad + (MobileTools.isMobile ? 24 * u : 0); // leave room for the status bar / notch
		var content = panel.content;

		// ---- Header
		y = place(content, Theme.text('MobileTools', 28 * u, Theme.TEXT, true), pad, y);
		y = place(content, Theme.text(deviceLine(), 13 * u, Theme.MUTED, false, contentWidth), pad, y + 2 * u);
		y = place(content, Theme.text(MobileTools.isSupported ? 'Native backend active' : 'No native backend: calls are no-ops on this target', 12 * u,
			MobileTools.isSupported ? Theme.OK : Theme.WARN, false, contentWidth), pad, y + 2 * u);

		// ---- Permissions
		y = section(content, 'Permissions', pad, y + 20 * u);

		var permissions:Array<{permission:Permission, title:String}> = [
			{permission: CAMERA, title: 'Camera'},
			{permission: MICROPHONE, title: 'Microphone'},
			{permission: LOCATION, title: 'Location (while in use)'},
			{permission: NOTIFICATIONS, title: 'Notifications'},
			{permission: IMAGES, title: 'Images'},
			{permission: AUDIO, title: 'Audio files'},
			{permission: STORAGE, title: 'Storage'},
			{permission: EXTERNAL_STORAGE, title: 'All files access'}
		];

		for (entry in permissions)
		{
			var row = new PermissionRow(entry.permission, entry.title, contentWidth, u, onPermissionTap);
			row.x = pad;
			row.y = y;
			content.addChild(row);
			rows.push(row);
			y += row.height + 8 * u;
		}

		y = addButton(content, new Button('Open app settings', contentWidth, 44 * u, 14 * u, function()
		{
			Permissions.openSettings();
			log('Opening app settings');
		}), pad, y + 4 * u);

		// ---- Haptics
		y = section(content, 'Haptics', pad, y + 20 * u);

		y = grid(content, [
			['Selection', function() Haptics.selection()],
			['Light', function() Haptics.impact(LIGHT)],
			['Medium', function() Haptics.impact(MEDIUM)],
			['Heavy', function() Haptics.impact(HEAVY)],
			['Soft', function() Haptics.impact(SOFT)],
			['Rigid', function() Haptics.impact(RIGID)],
			['Success', function() Haptics.notification(SUCCESS)],
			['Warning', function() Haptics.notification(WARNING)],
			['Error', function() Haptics.notification(ERROR)]
		], pad, y, contentWidth, 'Haptics');

		// ---- Toast, vibration, screen
		y = section(content, 'Toast, vibration and screen', pad, y + 20 * u);

		var keepButton:Button = null;
		keepButton = new Button(keepLabel(), contentWidth, 44 * u, 14 * u, function()
		{
			keepScreenOn = !keepScreenOn;
			MobileTools.setKeepScreenOn(keepScreenOn);
			keepButton.setText(keepLabel());
			log(keepScreenOn ? 'Screen will stay on' : 'Screen can turn off again');
		});

		y = grid(content, [
			['Short toast', function() MobileTools.showToast('Hello from extension-mobiletools!')],
			['Long toast', function() MobileTools.showToast('This toast stays a bit longer.', LONG)],
			['Vibrate 200 ms', function() MobileTools.vibrate(200)],
			['Stop vibration', function() MobileTools.cancelVibration()]
		], pad, y, contentWidth, null, 2);

		y = addButton(content, keepButton, pad, y + 8 * u);

		panel.setContentHeight(y + pad);

		// ---- Status bar showing the result of the last action (toasts don't exist on desktop)
		var bar = new Sprite();
		bar.graphics.beginFill(Theme.CARD);
		bar.graphics.drawRect(0, 0, width, barHeight);
		bar.graphics.endFill();
		bar.y = height - barHeight;
		addChild(bar);

		statusText = Theme.text('Tap a button to try a feature', 13 * u, Theme.MUTED, false, contentWidth);
		statusText.x = pad;
		statusText.y = (barHeight - statusText.height) / 2;
		bar.addChild(statusText);

		refreshAll();
	}

	// ---------------------------------------------------------------- permissions

	private function onPermissionTap(row:PermissionRow):Void
	{
		var status = Permissions.check(row.permission);

		// Nothing left to show: the only way to change it is the settings screen.
		if (status == DENIED_PERMANENTLY)
		{
			Permissions.openSettings();
			log('${row.title}: blocked, opening settings');
			return;
		}

		log('${row.title}: requesting...');

		Permissions.request(row.permission, function(result)
		{
			row.refresh();
			log('${row.title}: ${statusName(result)}');
		});
	}

	private function refreshAll():Void
	{
		for (row in rows)
			row.refresh();
	}

	public static function statusName(status:PermissionStatus):String
	{
		return switch (status)
		{
			case NOT_DETERMINED: 'not asked yet';
			case GRANTED: 'granted';
			case DENIED: 'denied';
			case DENIED_PERMANENTLY: 'blocked';
			case RESTRICTED: 'restricted';
		}
	}

	// ---------------------------------------------------------------- layout helpers

	private function log(message:String):Void
	{
		if (statusText != null)
			statusText.text = message;
	}

	private function deviceLine():String
	{
		if (!MobileTools.isSupported)
			return 'Not running on a mobile device';

		var info:DeviceInfo = MobileTools.getDeviceInfo();
		return '${info.manufacturer} ${info.model} - OS ${info.osVersion} (API ${info.apiLevel})';
	}

	private function keepLabel():String
	{
		return 'Keep screen on: ' + (keepScreenOn ? 'ON' : 'OFF');
	}

	/** Adds `child` at (x, y) and returns the y below it. */
	private function place(parent:Sprite, child:openfl.display.DisplayObject, x:Float, y:Float):Float
	{
		child.x = x;
		child.y = y;
		parent.addChild(child);
		return y + child.height;
	}

	private function addButton(parent:Sprite, button:Button, x:Float, y:Float):Float
	{
		return place(parent, button, x, y);
	}

	private function section(parent:Sprite, title:String, x:Float, y:Float):Float
	{
		return place(parent, Theme.text(title.toUpperCase(), 12 * u, Theme.ACCENT, true), x, y) + 10 * u;
	}

	/** Lays out buttons in a grid and returns the y below the last row. */
	private function grid(parent:Sprite, items:Array<Array<Dynamic>>, x:Float, y:Float, width:Float, logPrefix:String, columns:Int = 3):Float
	{
		var gap = 8 * u;
		var buttonWidth = (width - gap * (columns - 1)) / columns;
		var buttonHeight = 44 * u;

		for (i in 0...items.length)
		{
			var label:String = items[i][0];
			var action:Void->Void = items[i][1];

			var button = new Button(label, buttonWidth, buttonHeight, 13 * u, function()
			{
				action();
				log(logPrefix != null ? '$logPrefix: $label' : label);
			});

			button.x = x + (i % columns) * (buttonWidth + gap);
			button.y = y + Std.int(i / columns) * (buttonHeight + gap);
			parent.addChild(button);
		}

		var rowCount = Math.ceil(items.length / columns);
		return y + rowCount * (buttonHeight + gap) - gap;
	}
}

/**
 * One card per permission: its name, current status and a button to request it.
 */
private class PermissionRow extends Sprite
{
	public var permission(default, null):Permission;
	public var title(default, null):String;

	private var statusLabel:TextField;
	private var button:Button;
	private var unit:Float;
	private var cardWidth:Float;

	public function new(permission:Permission, title:String, width:Float, unit:Float, onTap:PermissionRow->Void)
	{
		super();

		this.permission = permission;
		this.title = title;
		this.unit = unit;
		this.cardWidth = width;

		var height = 64 * unit;

		graphics.beginFill(Theme.CARD);
		graphics.drawRoundRect(0, 0, width, height, 14 * unit, 14 * unit);
		graphics.endFill();

		var name = Theme.text(title, 15 * unit, Theme.TEXT, true);
		name.x = 14 * unit;
		name.y = 10 * unit;
		addChild(name);

		statusLabel = Theme.text('', 12 * unit, Theme.MUTED, true);
		statusLabel.x = 14 * unit;
		statusLabel.y = 34 * unit;
		addChild(statusLabel);

		var buttonWidth = 96 * unit;
		button = new Button('Request', buttonWidth, 38 * unit, 13 * unit, function() onTap(this), true);
		button.x = width - buttonWidth - 12 * unit;
		button.y = (height - 38 * unit) / 2;
		addChild(button);
	}

	public function refresh():Void
	{
		var status = Permissions.check(permission);

		statusLabel.text = Main.statusName(status);
		statusLabel.textColor = switch (status)
		{
			case GRANTED: Theme.OK;
			case DENIED: Theme.WARN;
			case DENIED_PERMANENTLY | RESTRICTED: Theme.BAD;
			case NOT_DETERMINED: Theme.MUTED;
		}

		button.setText(switch (status)
		{
			case GRANTED: 'Granted';
			case DENIED_PERMANENTLY: 'Settings';
			default: 'Request';
		});

		// Nothing left to ask once granted, so don't highlight it as an action.
		button.setPrimary(status != GRANTED);
	}
}
