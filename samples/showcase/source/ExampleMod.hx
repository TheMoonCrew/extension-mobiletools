import haxe.io.Path;
import mobiletools.mods.ModFiles;

/**
 * A tiny mod the showcase can write to disk, so you can try the mod system without copying files by hand.
 * It is the same layout a real mod uses: a `mod.json` and scripts in `scripts/`.
 */
class ExampleMod
{
	public static inline var ID:String = 'hello-mod';

	private static inline var INFO:String = '{
	"id": "hello-mod",
	"name": "Hello Mod",
	"version": "1.0.0",
	"author": "MobileTools",
	"description": "Shows a toast when loaded and reacts to the onTap event."
}';

	private static inline var SCRIPT:String = '// Declare variables before the functions that use them.
var taps = 0;

function onLoad() {
	mod.log("Hello from a script! Running on " + (mobile.isMobile ? "mobile" : "desktop"));
	mobile.showToast("Hello Mod loaded");
}

function onUnload() {
	mod.log("Bye!");
}

// The showcase calls this from the "Fire onTap" button.
function onTap() {
	taps++;
	mobile.impact("light");
	mod.log("tapped " + taps + " time(s)");
	return taps;
}
';

	/** Writes the mod into `modsFolder`. Returns `false` if the folder is not writable. */
	public static function install(modsFolder:String):Bool
	{
		var folder = Path.join([modsFolder, ID]);

		return ModFiles.ensureDirectory(Path.join([folder, 'scripts']))
			&& ModFiles.writeText(Path.join([folder, 'mod.json']), INFO)
			&& ModFiles.writeText(Path.join([folder, 'scripts', 'main.hx']), SCRIPT);
	}
}
