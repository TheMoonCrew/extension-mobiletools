import haxe.io.Path;
import mobiletools.mods.ModFiles;

/**
 * A tiny mod the showcase can write to disk, so you can try the mod system without copying files by hand.
 * It is the same layout a real mod uses: a `mod.json`, scripts in `scripts/` and haptic patterns in `haptics/`.
 */
class ExampleMod
{
	public static inline var ID:String = 'hello-mod';

	private static inline var INFO:String = '{
	"id": "hello-mod",
	"name": "Hello Mod",
	"version": "1.1.0",
	"author": "MobileTools",
	"description": "Shows a toast when loaded, adds haptic patterns and reacts to the onTap event."
}';

	// A pattern shipped as a file. It shows up by name, next to the built in ones, while the mod is enabled.
	private static inline var WAVE:String = '{
	"name": "hello-wave",
	"events": [
		{"time": 0, "intensity": 0.3, "sharpness": 0.2, "duration": 120},
		{"time": 140, "intensity": 0.6, "sharpness": 0.2, "duration": 120},
		{"time": 280, "intensity": 1.0, "sharpness": 0.4, "duration": 160},
		{"time": 480, "intensity": 1.0, "sharpness": 1.0}
	]
}';

	// The same name as a built in pattern: while this mod is enabled, "knock" feels different.
	private static inline var KNOCK:String = '{
	"events": [
		{"time": 0, "intensity": 1.0, "sharpness": 1.0},
		{"time": 70, "intensity": 0.7, "sharpness": 1.0},
		{"time": 260, "intensity": 1.0, "sharpness": 1.0},
		{"time": 330, "intensity": 0.7, "sharpness": 1.0}
	]
}';

	private static inline var SCRIPT:String = '// Declare variables before the functions that use them.
var taps = 0;

// Patterns can also be built in code and saved by name. They disappear when the mod is disabled.
haptics.define("hello-burst", haptics.pattern()
	.tap(0, 1, 1)
	.hold(60, 200, 0.7, 0.3)
	.ramp(280, 300, 0.7, 0));

function onLoad() {
	mod.log("Hello from a script! Running on " + (mobile.isMobile ? "mobile" : "desktop"));
	mod.log("Haptic patterns here: " + haptics.names().join(", "));
	mobile.showToast("Hello Mod loaded");
	haptics.play("hello-wave");
}

function onUnload() {
	mod.log("Bye!");
}

// The showcase calls this from the "Fire onTap" button.
function onTap() {
	taps++;

	// Every third tap plays the burst, the others the wave from haptics/hello-wave.json.
	haptics.play(taps % 3 == 0 ? "hello-burst" : "hello-wave");
	mod.log("tapped " + taps + " time(s)");
	return taps;
}
';

	/** Writes the mod into `modsFolder`. Returns `false` if the folder is not writable. */
	public static function install(modsFolder:String):Bool
	{
		var folder = Path.join([modsFolder, ID]);

		return ModFiles.ensureDirectory(Path.join([folder, 'scripts']))
			&& ModFiles.ensureDirectory(Path.join([folder, 'haptics']))
			&& ModFiles.writeText(Path.join([folder, 'mod.json']), INFO)
			&& ModFiles.writeText(Path.join([folder, 'scripts', 'main.hx']), SCRIPT)
			&& ModFiles.writeText(Path.join([folder, 'haptics', 'hello-wave.json']), WAVE)
			&& ModFiles.writeText(Path.join([folder, 'haptics', 'knock.json']), KNOCK);
	}
}
