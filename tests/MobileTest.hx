import Check.*;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import mobiletools.FilePicker;
import mobiletools.MobileTools;
import mobiletools.SafeArea;
import mobiletools.backend.NullBackend;
import mobiletools.mods.Mod;
import mobiletools.mods.ModArchive;
import mobiletools.mods.ModFiles;
import mobiletools.mods.ModInfo;
import mobiletools.mods.ModManager;
import mobiletools.scripting.Script;
import sys.FileSystem;
import sys.io.File;

/**
 * Remembers fullscreen calls and reports a fixed safe area, so they can be checked without a phone.
 */
class ScreenBackend extends NullBackend
{
	public var fullscreenCalls:Array<Bool> = [];
	public var safeArea:SafeArea = {top: 88, right: 0, bottom: 34, left: 0};

	override public function setFullscreen(enabled:Bool):Void
	{
		fullscreenCalls.push(enabled);
	}

	override public function getSafeArea():SafeArea
	{
		return safeArea;
	}
}

private typedef ZipFile =
{
	var name:String;
	var content:String;
}

/**
 * Tests for the mobile features: fullscreen and the safe area, the file picker fallback, installing mods from zip
 * files, uninstalling, `platforms` in mod.json and the app event hooks. Run with the others:
 *
 *     haxe tests/test.hxml
 */
class MobileTest
{
	static var base:String;
	static var root:String;
	static var errors:Array<String> = [];

	static function main():Void
	{
		var original = Sys.getCwd();
		var parent = Sys.getEnv('TEMP') != null ? Sys.getEnv('TEMP') : (Sys.getEnv('TMPDIR') != null ? Sys.getEnv('TMPDIR') : '/tmp');
		var temp = parent + '/mobiletools-mobile-tests-' + Std.int(Sys.time());
		ModFiles.ensureDirectory(temp);
		Sys.setCwd(temp);

		base = FileSystem.fullPath('.');
		root = base + '/mods';

		testScreen();
		testFilePicker();
		testArchive();
		testInstall();
		testInstallSafety();
		testUninstall();
		testPlatforms();
		testAppEvents();

		Sys.setCwd(original);
		ModFiles.deleteRecursive(temp);

		Sys.exit(Check.finish());
	}

	// ---------------------------------------------------------------- helpers

	static function makeZip(path:String, files:Array<ZipFile>, compress:Bool = true):Void
	{
		var entries = new List<haxe.zip.Entry>();

		for (file in files)
		{
			var data = Bytes.ofString(file.content);
			var entry:haxe.zip.Entry = {
				fileName: file.name,
				fileSize: data.length,
				fileTime: Date.now(),
				compressed: false,
				dataSize: data.length,
				data: data,
				crc32: haxe.crypto.Crc32.make(data)
			};

			if (compress && !StringTools.endsWith(file.name, '/'))
				haxe.zip.Tools.compress(entry, 6);

			entries.add(entry);
		}

		var output = new BytesOutput();
		new haxe.zip.Writer(output).write(entries);
		ModFiles.ensureDirectory(haxe.io.Path.directory(path));
		File.saveBytes(path, output.getBytes());
	}

	/** Overwrites a 32 bit field of `name`'s central directory record, to fake what some zip tools write. */
	static function patchCentral(path:String, name:String, offset:Int, value:Int):Void
	{
		var bytes = File.getBytes(path);
		var i = 0;

		while (i + 46 < bytes.length)
		{
			if (bytes.getInt32(i) == 0x02014b50 && bytes.getString(i + 46, bytes.getUInt16(i + 28)) == name)
			{
				bytes.setInt32(i + offset, value);
				File.saveBytes(path, bytes);
				return;
			}

			i++;
		}

		throw 'No central record for $name';
	}

	static function write(path:String, content:String):Void
	{
		ModFiles.ensureDirectory(haxe.io.Path.directory(path));
		ModFiles.writeText(path, content);
	}

	static function errorsFor(source:String):Array<String>
	{
		return errors.filter(e -> StringTools.startsWith(e, source + ': '));
	}

	// ---------------------------------------------------------------- screen

	static function testScreen():Void
	{
		var backend = new ScreenBackend();
		MobileTools.setBackend(backend);

		check(!MobileTools.isFullscreen, 'not fullscreen by default');
		MobileTools.setFullscreen(true);
		check(MobileTools.isFullscreen, 'setFullscreen(true) is remembered');
		MobileTools.setFullscreen(false);
		check(!MobileTools.isFullscreen, 'setFullscreen(false) is remembered');
		equals(backend.fullscreenCalls.join(','), 'true,false', 'setFullscreen reaches the backend');

		equals(MobileTools.getSafeArea().top, 88, 'getSafeArea comes from the backend');

		equals(SafeAreaTools.parse('1,2,3,4').left, 4, 'parses native safe area strings');
		equals(SafeAreaTools.parse('1,2,3,4').right, 2, 'keeps the edge order top, right, bottom, left');
		equals(SafeAreaTools.parse('1,2,3').top, 0, 'a short string gives no insets');
		equals(SafeAreaTools.parse('1,x,3,4').top, 0, 'a malformed number gives no insets');
		equals(SafeAreaTools.parse('-1,0,0,0').top, 0, 'negative insets are refused');
		equals(SafeAreaTools.parse(null).bottom, 0, 'null gives no insets');

		// Scripts can look, not touch.
		MobileTools.setFullscreen(true);
		var script = Script.fromString('function f() return [mobile.isFullscreen(), mobile.getSafeArea().bottom, mobile.platform];', 'screen');
		var result:Array<Dynamic> = script.call('f');
		equals(result[0], true, 'scripts see the fullscreen state');
		equals(result[1], 34, 'scripts see the safe area');
		equals(result[2], 'desktop', 'scripts see the platform');
		throwsWith(function() Script.fromString('function f() mobile.setFullscreen(false);', 'set').call('f'), 'set:f', 'scripts cannot change fullscreen');

		MobileTools.setFullscreen(false);
		MobileTools.setBackend(new NullBackend());
	}

	static function testFilePicker():Void
	{
		var got:Dynamic = 'not called';
		FilePicker.pick(['zip'], function(path) got = path);
		equals(got, null, 'without a native backend the picker answers null at once');
		check(!FilePicker.isOpen, 'and is not left open');

		var imported:Dynamic = 'not called';
		ModManager.importFromDevice(function(mod) imported = mod);
		equals(imported, null, 'importFromDevice() answers null without a picker');
	}

	// ---------------------------------------------------------------- archives

	static function testArchive():Void
	{
		var path = base + '/zips/plain.zip';
		var big = StringTools.lpad('', 'abc', 5000);

		makeZip(path, [{name: 'folder/', content: ''}, {name: 'folder/a.txt', content: 'hello'}, {name: 'big.txt', content: big}, {name: 'empty.txt', content: ''}]);

		var archive = ModArchive.open(path);
		equals(archive.entries.length, 4, 'lists every entry');
		check(archive.get('folder/').isDirectory, 'recognises folders');
		equals(archive.read(archive.get('folder/a.txt')).toString(), 'hello', 'reads a deflated entry');
		equals(archive.read(archive.get('big.txt')).toString(), big, 'reads a larger deflated entry');
		equals(archive.read(archive.get('empty.txt')).length, 0, 'reads an empty entry');
		archive.close();

		var stored = base + '/zips/stored.zip';
		makeZip(stored, [{name: 'a.txt', content: 'plain'}], false);
		archive = ModArchive.open(stored);
		equals(archive.get('a.txt').method, 0, 'stored entries are recognised');
		equals(archive.read(archive.get('a.txt')).toString(), 'plain', 'reads a stored entry');
		archive.close();

		// An entry claiming to be smaller than it is must not be trusted.
		var lying = base + '/zips/lying.zip';
		makeZip(lying, [{name: 'big.txt', content: big}]);
		patchCentral(lying, 'big.txt', 24, 10);
		archive = ModArchive.open(lying);
		throwsWith(function() archive.read(archive.get('big.txt')), 'Damaged archive', 'refuses data larger than declared');
		archive.close();

		var corrupt = base + '/zips/corrupt.zip';
		makeZip(corrupt, [{name: 'a.txt', content: 'hello'}], false);
		patchCentral(corrupt, 'a.txt', 16, 12345);
		archive = ModArchive.open(corrupt);
		throwsWith(function() archive.read(archive.get('a.txt')), 'checksum', 'refuses data that fails its CRC');
		archive.close();

		write(base + '/zips/not-a-zip.zip', 'just text');
		throwsWith(function() ModArchive.open(base + '/zips/not-a-zip.zip'), 'Not a zip', 'refuses files that are not zips');
		throwsWith(function() ModArchive.open(base + '/zips/missing.zip'), 'Could not open', 'reports a missing file');

		var encrypted = base + '/zips/encrypted.zip';
		makeZip(encrypted, [{name: 'a.txt', content: 'x'}], false);
		// General purpose flags share a 32 bit word with the version needed: set bit 0 of the flags.
		patchCentral(encrypted, 'a.txt', 6, 20 | (1 << 16));
		throwsWith(function() ModArchive.open(encrypted), 'Encrypted', 'refuses encrypted archives');
	}

	// ---------------------------------------------------------------- installing

	static function testInstall():Void
	{
		ModManager.onError = function(source, message) errors.push('$source: $message');
		ModManager.onLog = function(source, message) {};
		ModManager.stateFile = base + '/state/mods.json';
		ModManager.addRoot(root);
		ModManager.init();

		equals(ModManager.getRoots()[0], root, 'the first root is where mods get installed');

		// mod.json at the top of the archive, no id: the archive name becomes the id.
		var flat = base + '/zips/Cool Colors (v2).zip';
		makeZip(flat, [{name: 'mod.json', content: '{"name": "Cool Colors"}'}, {name: 'data/palette.txt', content: 'blue'}]);

		var mod = ModManager.install(flat);
		check(mod != null, 'installs a zip with mod.json at the top');
		equals(mod != null ? mod.id : null, 'Cool-Colors-v2', 'derives a valid id from the archive name');
		check(mod != null && !mod.enabled, 'a new mod starts disabled');
		check(FileSystem.exists(root + '/Cool-Colors-v2/data/palette.txt'), 'files land in the mods folder');
		check(ModManager.get('Cool-Colors-v2') != null, 'the mod is listed straight away');

		// The mod in a folder, with the junk macOS adds and an explicit id.
		var foldered = base + '/zips/fancy.zip';
		makeZip(foldered, [
			{name: 'fancy-1.0/', content: ''},
			{name: 'fancy-1.0/mod.json', content: '{"id": "fancy", "name": "Fancy", "version": "1.0"}'},
			{name: 'fancy-1.0/scripts/main.hx', content: 'function onLoad() mod.log("v1"); function version() return 1;'},
			{name: 'fancy-1.0/.DS_Store', content: 'junk'},
			{name: '__MACOSX/fancy-1.0/._mod.json', content: 'junk'}
		]);

		mod = ModManager.install(foldered);
		check(mod != null && mod.id == 'fancy', 'installs a zip holding the mod folder, using the id in mod.json');
		check(FileSystem.exists(root + '/fancy/scripts/main.hx'), 'unpacks into a folder named after the id');
		check(!FileSystem.exists(root + '/fancy/.DS_Store') && !FileSystem.exists(root + '/__MACOSX'), 'skips files zip tools add');
		check(ModManager.enable('fancy'), 'an installed mod can be enabled');
		equals(ModManager.call('version').join(','), '1', 'its scripts run');

		// Updating keeps it enabled and runs the new scripts.
		var update = base + '/zips/fancy-2.zip';
		makeZip(update, [
			{name: 'mod.json', content: '{"id": "fancy", "name": "Fancy", "version": "2.0"}'},
			{name: 'scripts/main.hx', content: 'function version() return 2;'}
		]);

		mod = ModManager.install(update);
		check(mod != null && mod.enabled, 'an update keeps an enabled mod enabled');
		equals(mod != null ? mod.info.version : null, '2.0', 'the update replaces mod.json');
		equals(ModManager.call('version').join(','), '2', 'the update replaces the scripts');
		check(!FileSystem.exists(root + '/fancy/.DS_Store'), 'files of the old version are gone');

		var leftovers = [for (entry in FileSystem.readDirectory(root)) if (StringTools.startsWith(entry, '.')) entry];
		equals(leftovers.length, 0, 'no staging folder is left behind');
	}

	static function testInstallSafety():Void
	{
		var before = FileSystem.readDirectory(root).length;

		function refused(name:String, files:Array<ZipFile>, expected:String, description:String):Void
		{
			var path = base + '/zips/' + name;
			makeZip(path, files);
			errors = [];
			check(ModManager.install(path) == null, description);
			check(errorsFor(name).filter(e -> e.indexOf(expected) >= 0).length == 1, '$description: reports "$expected" (got ${errors.join(" / ")})');
		}

		refused('escape.zip', [{name: 'mod.json', content: '{"id": "escape", "name": "Escape"}'}, {name: '../../escaped.txt', content: 'x'}], 'outside the mod folder', 'refuses entries that climb out with ..');
		check(!FileSystem.exists(base + '/escaped.txt') && !FileSystem.exists(root + '/../escaped.txt'), 'nothing was written outside');

		refused('absolute.zip', [{name: 'mod.json', content: '{"id": "absolute", "name": "Absolute"}'}, {name: '/tmp/mobiletools-absolute.txt', content: 'x'}], 'outside the mod folder', 'refuses absolute entries');
		refused('nomod.zip', [{name: 'readme.txt', content: 'hi'}], 'no mod.json', 'refuses archives without mod.json');
		refused('two.zip', [{name: 'a/mod.json', content: '{"name": "A"}'}, {name: 'b/mod.json', content: '{"name": "B"}'}], 'several mods', 'refuses archives with several mods');
		refused('noname.zip', [{name: 'mod.json', content: '{"id": "x"}'}], '"name"', 'refuses an invalid mod.json');

		// The folder the mod would go to holds something else: it must not be deleted.
		write(root + '/squatter/mod.json', '{"id": "other", "name": "Other"}');
		write(root + '/squatter/keep.txt', 'mine');
		refused('squatter.zip', [{name: 'mod.json', content: '{"id": "squatter", "name": "Squatter"}'}], 'already exists', 'refuses to install over a folder holding another mod');
		equals(ModFiles.readText(root + '/squatter/keep.txt'), 'mine', 'and leaves that folder alone');
		ModFiles.deleteRecursive(root + '/squatter');

		// A mod in another root, in a folder not named after its id, is updated where it is.
		var elsewhere = base + '/other-root';
		write(elsewhere + '/Taken Folder/mod.json', '{"id": "taken", "name": "Taken", "version": "1"}');
		ModManager.addRoot(elsewhere);
		var takenZip = base + '/zips/taken.zip';
		makeZip(takenZip, [{name: 'mod.json', content: '{"id": "taken", "name": "Taken", "version": "2"}'}]);
		var taken = ModManager.install(takenZip);
		check(taken != null && taken.info.version == '2', 'updates a mod living in another root');
		check(taken != null && taken.path == elsewhere + '/Taken Folder', 'in its own folder');
		check(!FileSystem.exists(root + '/taken'), 'without a second copy in installRoot');
		ModManager.removeRoot(elsewhere);
		ModManager.reload();

		// A mod.json claiming to be enormous is refused before it is read.
		var bomb = base + '/zips/bomb.zip';
		makeZip(bomb, [{name: 'mod.json', content: '{"id": "bomb", "name": "Bomb"}'}]);
		patchCentral(bomb, 'mod.json', 24, 0x7ffffff0);
		errors = [];
		check(ModManager.install(bomb) == null, 'refuses an archive declaring a huge mod.json');
		check(errorsFor('bomb.zip').filter(e -> e.indexOf('MB allowed') >= 0).length == 1, 'because of its declared size');

		// Limits
		ModManager.maxInstallSize = 100;
		refused('huge.zip', [{name: 'mod.json', content: '{"id": "huge", "name": "Huge"}'}, {name: 'big.txt', content: StringTools.lpad('', 'x', 500)}], 'MB allowed', 'refuses mods over maxInstallSize');
		ModManager.maxInstallSize = 256 * 1024 * 1024;

		ModManager.maxInstallFiles = 2;
		refused('many.zip', [for (i in 0...4) {name: i == 0 ? 'mod.json' : 'f$i.txt', content: i == 0 ? '{"id": "many", "name": "Many"}' : 'x'}], 'files, more than', 'refuses mods over maxInstallFiles');
		ModManager.maxInstallFiles = 10000;

		// A damaged update must leave the installed version alone.
		var damaged = base + '/zips/fancy-damaged.zip';
		makeZip(damaged, [{name: 'mod.json', content: '{"id": "fancy", "name": "Fancy", "version": "3.0"}'}, {name: 'scripts/main.hx', content: 'function version() return 3;'}], false);
		patchCentral(damaged, 'scripts/main.hx', 16, 999);
		errors = [];
		check(ModManager.install(damaged) == null, 'refuses a damaged update');
		equals(ModManager.get('fancy').info.version, '2.0', 'the installed version is untouched');
		equals(ModManager.call('version').join(','), '2', 'and still runs');

		// Symbolic links inside an archive are never created.
		var linked = base + '/zips/linked.zip';
		makeZip(linked, [{name: 'mod.json', content: '{"id": "linked", "name": "Linked"}'}, {name: 'link', content: '/etc/passwd'}], false);
		patchCentral(linked, 'link', 38, 0xa1ff << 16);
		check(ModManager.install(linked) != null, 'installs an archive containing a symbolic link');
		check(!FileSystem.exists(root + '/linked/link'), 'but skips the link');

		ModManager.uninstall('linked');
		equals(FileSystem.readDirectory(root).length, before, 'refused installs leave the mods folder as it was');
	}

	static function testUninstall():Void
	{
		write(root + '/needs-fancy/mod.json', '{"name": "Needs Fancy", "dependencies": ["fancy"]}');
		ModManager.reload();
		check(ModManager.enable('needs-fancy'), 'a dependent mod enables');

		check(ModManager.uninstall('fancy'), 'uninstall() succeeds');
		check(!FileSystem.exists(root + '/fancy'), 'the folder is deleted');
		check(ModManager.get('fancy') == null, 'the mod is no longer listed');
		check(!ModManager.isEnabled('needs-fancy'), 'mods depending on it are disabled');
		check(!ModManager.uninstall('fancy'), 'uninstalling twice returns false');
		check(!ModManager.uninstall('ghost'), 'uninstalling an unknown mod returns false');

		// A link inside a mod folder is removed, not followed.
		if (Sys.systemName() != 'Windows')
		{
			write(base + '/precious/photo.txt', 'keep me');
			write(root + '/linker/mod.json', '{"name": "Linker"}');
			Sys.command('ln', ['-s', base + '/precious', root + '/linker/photos']);
			ModManager.reload();

			check(ModManager.uninstall('linker'), 'uninstalls a mod containing a link');
			check(FileSystem.exists(base + '/precious/photo.txt'), 'the folder the link pointed to is untouched');
		}
	}

	static function testPlatforms():Void
	{
		write(root + '/phone-only/mod.json', '{"name": "Phone Only", "platforms": ["mobile"]}');
		write(root + '/ios-only/mod.json', '{"name": "iOS Only", "platforms": ["ios"]}');
		write(root + '/desktop-ok/mod.json', '{"name": "Desktop OK", "platforms": ["android", "Desktop"]}');
		ModManager.reload();

		var phone = ModManager.get('phone-only');
		check(phone.error != null && phone.error.indexOf('mobile') >= 0, 'a mobile only mod explains why it is off on desktop');
		check(!ModManager.enable('phone-only'), 'and cannot be enabled');
		check(ModManager.enable('desktop-ok'), 'platform names are not case sensitive');

		ModManager.platform = 'android';
		ModManager.reload();
		check(ModManager.get('phone-only').error == null, '"mobile" covers Android');
		check(ModManager.enable('phone-only'), 'so it enables there');
		check(!ModManager.enable('ios-only'), 'an iOS mod does not enable on Android');

		ModManager.platform = 'ios';
		ModManager.reload();
		check(ModManager.isEnabled('phone-only'), '"mobile" covers iOS too');
		check(ModManager.enable('ios-only'), 'an iOS mod enables on iOS');
		check(!ModManager.isEnabled('desktop-ok'), 'a mod enabled before stays off where it is not supported');

		equals(ModInfoTools.parse('{"name": "x"}', 'x').platforms, null, 'platforms is optional');
		throwsWith(function() ModInfoTools.parse('{"name": "x", "platforms": "ios"}', 'x'), 'list of strings', 'platforms must be a list');

		ModManager.platform = 'desktop';
		ModManager.reload();
	}

	static function testAppEvents():Void
	{
		write(root + '/events/mod.json', '{"name": "Events"}');
		write(root + '/events/scripts/main.hx', 'var seen = [];\nfunction onPause() seen.push("pause");\nfunction onResume() seen.push("resume");\nfunction onResize(w, h) seen.push(w + "x" + h);');
		ModManager.reload();
		check(ModManager.enable('events'), 'a mod with app event hooks enables');

		ModManager.pause();
		ModManager.resume();
		ModManager.resize(1080, 2400);

		var seen:Array<String> = ModManager.get('events').scripts[0].get('seen');
		equals(seen.join(','), 'pause,resume,1080x2400', 'pause(), resume() and resize() reach the hooks');
	}
}
