package mobiletools;

import haxe.Timer;

/**
 * Lets the user choose a file with the system picker (the Files app on iOS, the document picker on Android),
 * and hands back a private copy the app can read with normal file functions.
 *
 * ```haxe
 * FilePicker.pick(['zip'], function(path)
 * {
 *     if (path != null)
 *         trace('Got ' + path);
 * });
 * ```
 *
 * The copy lives in the app's cache folder and is replaced by the next pick, so move it if you want to keep it.
 * On targets without a native backend the callback receives `null` straight away.
 */
class FilePicker
{
	/** How often an open picker is checked for a result, in milliseconds. */
	private static inline var POLL_INTERVAL:Int = 100;

	private static var timer:Timer;
	private static var callback:Null<String>->Void;

	/** `true` while the picker is on screen. */
	public static var isOpen(get, never):Bool;

	/**
	 * Shows the picker.
	 *
	 * @param extensions File extensions to offer, without the dot (e.g. `['zip']`). Empty or `null` allows any file.
	 *                   Android may still let other files through when their type is unknown, so check what you get.
	 * @param onPicked   Receives the path of the copy, or `null` when the user cancelled, the file could not be
	 *                   copied, another picker is already open or the target has no picker. Runs on the main thread.
	 */
	public static function pick(extensions:Array<String>, onPicked:Null<String>->Void):Void
	{
		var backend = MobileTools.backend;
		var clean = extensions != null ? [for (extension in extensions) cleanExtension(extension)].filter(e -> e != '') : [];

		if (callback != null || !backend.isNative || !backend.pickFile(clean.join(',')))
		{
			if (onPicked != null)
				onPicked(null);

			return;
		}

		callback = onPicked != null ? onPicked : function(_) {};
		timer = new Timer(POLL_INTERVAL);
		timer.run = poll;
	}

	private static function poll():Void
	{
		var backend = MobileTools.backend;

		if (backend.isFilePickerPending())
			return;

		timer.stop();
		timer = null;

		var done = callback;
		var path = backend.getPickedFile();
		callback = null;

		done(path != null && path != '' ? path : null);
	}

	/** Lowercase, no leading dot, and nothing that could break the comma separated list sent to the backend. */
	private static function cleanExtension(extension:String):String
	{
		if (extension == null)
			return '';

		var clean = StringTools.trim(extension).toLowerCase();

		while (StringTools.startsWith(clean, '.'))
			clean = clean.substr(1);

		return ~/^[a-z0-9_+\-]+$/.match(clean) ? clean : '';
	}

	@:noCompletion private static inline function get_isOpen():Bool
	{
		return callback != null;
	}
}
