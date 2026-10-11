package com.mobiletools;

import android.app.Activity;
import android.app.AlarmManager;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.content.pm.PackageManager;
import android.graphics.Insets;
import android.hardware.biometrics.BiometricManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.OpenableColumns;
import android.provider.Settings;
import android.view.DisplayCutout;
import android.view.View;
import android.view.ViewTreeObserver;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.MimeTypeMap;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.Callable;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;

import org.haxe.extension.Extension;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Native side of extension-mobiletools. Every public static method is called from
 * Haxe through JNI (see AndroidBackend.hx), so signatures must stay in sync.
 */
public class MobileTools extends Extension
{
	// Must match mobiletools.PermissionStatus
	private static final int STATUS_NOT_DETERMINED = 0;
	private static final int STATUS_GRANTED = 1;
	private static final int STATUS_DENIED = 2;
	private static final int STATUS_DENIED_PERMANENTLY = 3;
	private static final int STATUS_RESTRICTED = 4;

	private static final int PERMISSION_REQUEST_CODE = 7391;
	private static final String PREFS_NAME = "mobiletools_permissions";
	private static final int PICK_FILE_REQUEST_CODE = 7398;
	private static final String PICKED_FOLDER = "mobiletools_picked";

	/** Far more than any real pattern needs (HapticPattern allows 256 events), but stops absurd input early. */
	private static final int MAX_WAVEFORM_SEGMENTS = 1024;

	/** Set by setFullscreen(), read on the UI thread to apply it again after the app or a dialog gave focus back. */
	private static volatile boolean fullscreen = false;
	private static boolean focusListenerAdded = false;

	/** Set by pickFile() until the chosen file is copied or the picker is closed. */
	private static volatile boolean pickPending = false;
	private static volatile String pickedPath = "";

	/** Permission ids (see mobiletools.Permission) whose system prompt is currently showing. */
	private static final Set<String> pendingRequests = Collections.synchronizedSet(new HashSet<String>());

	public static void showToast(final String message, final int duration)
	{
		final Activity activity = Extension.mainActivity;

		if (activity == null)
			return;

		activity.runOnUiThread(new Runnable()
		{
			@Override
			public void run()
			{
				Toast.makeText(activity, message, duration == 1 ? Toast.LENGTH_LONG : Toast.LENGTH_SHORT).show();
			}
		});
	}

	@SuppressWarnings("deprecation")
	public static void vibrate(int milliseconds)
	{
		Vibrator vibrator = getVibrator();

		if (vibrator == null || !vibrator.hasVibrator())
			return;

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			vibrator.vibrate(VibrationEffect.createOneShot(milliseconds, VibrationEffect.DEFAULT_AMPLITUDE));
		else
			vibrator.vibrate(milliseconds);
	}

	public static void cancelVibration()
	{
		Vibrator vibrator = getVibrator();

		if (vibrator != null)
			vibrator.cancel();
	}

	public static void setKeepScreenOn(final boolean enabled)
	{
		final Activity activity = Extension.mainActivity;

		if (activity == null)
			return;

		activity.runOnUiThread(new Runnable()
		{
			@Override
			public void run()
			{
				if (enabled)
					activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
				else
					activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
			}
		});
	}

	// ---------------------------------------------------------------- fullscreen

	public static void setFullscreen(final boolean enabled)
	{
		fullscreen = enabled;

		final Activity activity = Extension.mainActivity;

		if (activity == null)
			return;

		activity.runOnUiThread(new Runnable()
		{
			@Override
			public void run()
			{
				watchFocus(activity);
				applyFullscreen(activity, enabled);
			}
		});
	}

	/**
	 * Returns "top,right,bottom,left": how many pixels of the game's view, on each edge, are under system bars
	 * or a display cutout. Measured against the view rather than the window, so bars the view doesn't extend
	 * under (outside fullscreen) don't count.
	 */
	public static String getSafeArea()
	{
		final Activity activity = Extension.mainActivity;

		if (activity == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M)
			return "0,0,0,0";

		String result = callOnUiThread(activity, new Callable<String>()
		{
			@Override
			public String call()
			{
				return measureSafeArea(activity);
			}
		});

		return result != null ? result : "0,0,0,0";
	}

	/** Must run on the UI thread. */
	@SuppressWarnings("deprecation")
	private static void applyFullscreen(Activity activity, boolean enabled)
	{
		Window window = activity.getWindow();

		if (window == null)
			return;

		// Without this the area next to a notch stays black instead of showing the game.
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
		{
			WindowManager.LayoutParams attributes = window.getAttributes();
			int mode = enabled ? WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES : WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT;

			if (attributes.layoutInDisplayCutoutMode != mode)
			{
				attributes.layoutInDisplayCutoutMode = mode;
				window.setAttributes(attributes);
			}
		}

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
		{
			WindowInsetsController controller = window.getInsetsController();

			if (controller != null)
			{
				if (enabled)
				{
					controller.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
					controller.hide(WindowInsets.Type.systemBars());
				}
				else
				{
					controller.show(WindowInsets.Type.systemBars());
				}

				return;
			}
		}

		View decor = window.getDecorView();

		if (enabled)
		{
			// The same flags SDL uses for its own fullscreen, so the two never fight over them.
			int flags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
				| View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_FULLSCREEN;

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT)
				flags |= View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;

			decor.setSystemUiVisibility(flags);
			window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
		}
		else
		{
			decor.setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_VISIBLE);
			window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
		}
	}

	/**
	 * Dialogs (permission prompts, the keyboard, system popups) can bring the bars back. Applying fullscreen again
	 * whenever the window regains focus is what Android recommends. SDL already owns the system UI visibility
	 * listener, so this uses the focus listener instead of replacing it. Must run on the UI thread.
	 */
	private static void watchFocus(final Activity activity)
	{
		if (focusListenerAdded || activity.getWindow() == null)
			return;

		focusListenerAdded = true;

		activity.getWindow().getDecorView().getViewTreeObserver().addOnWindowFocusChangeListener(new ViewTreeObserver.OnWindowFocusChangeListener()
		{
			@Override
			public void onWindowFocusChanged(boolean hasFocus)
			{
				if (hasFocus && fullscreen)
					applyFullscreen(activity, true);
			}
		});
	}

	/** Must run on the UI thread. */
	@SuppressWarnings("deprecation")
	private static String measureSafeArea(Activity activity)
	{
		Window window = activity.getWindow();

		if (window == null)
			return null;

		View decor = window.getDecorView();
		WindowInsets insets = decor.getRootWindowInsets();

		if (insets == null)
			return null;

		int top, right, bottom, left;

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
		{
			// Hidden bars report zero here, so in fullscreen only the cutout is left.
			Insets values = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
			top = values.top;
			right = values.right;
			bottom = values.bottom;
			left = values.left;
		}
		else
		{
			top = insets.getSystemWindowInsetTop();
			right = insets.getSystemWindowInsetRight();
			bottom = insets.getSystemWindowInsetBottom();
			left = insets.getSystemWindowInsetLeft();

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
			{
				DisplayCutout cutout = insets.getDisplayCutout();

				if (cutout != null)
				{
					top = Math.max(top, cutout.getSafeInsetTop());
					right = Math.max(right, cutout.getSafeInsetRight());
					bottom = Math.max(bottom, cutout.getSafeInsetBottom());
					left = Math.max(left, cutout.getSafeInsetLeft());
				}
			}
		}

		// The insets are relative to the window. Remove the part the game's view doesn't cover anyway.
		View view = Extension.mainView != null ? Extension.mainView : decor;
		int[] position = new int[2];
		view.getLocationInWindow(position);

		int viewTop = position[1];
		int viewLeft = position[0];
		int viewBottom = decor.getHeight() - (position[1] + view.getHeight());
		int viewRight = decor.getWidth() - (position[0] + view.getWidth());

		return Math.max(0, top - viewTop) + "," + Math.max(0, right - viewRight) + "," + Math.max(0, bottom - viewBottom) + "," + Math.max(0, left - viewLeft);
	}

	/** Runs task on the UI thread and waits for it, since views must only be read there. Null on timeout or failure. */
	private static <T> T callOnUiThread(Activity activity, Callable<T> task)
	{
		try
		{
			if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper())
				return task.call();

			FutureTask<T> future = new FutureTask<T>(task);
			activity.runOnUiThread(future);
			return future.get(500, TimeUnit.MILLISECONDS);
		}
		catch (Exception e)
		{
			return null;
		}
	}

	/** Coming back from the background resets the system bars, so hide them again. */
	@Override
	public void onResume()
	{
		final Activity activity = Extension.mainActivity;

		if (!fullscreen || activity == null)
			return;

		activity.runOnUiThread(new Runnable()
		{
			@Override
			public void run()
			{
				applyFullscreen(activity, fullscreen);
			}
		});
	}

	/** Returns a JSON object matching the `mobiletools.DeviceInfo` typedef. */
	public static String getDeviceInfo()
	{
		JSONObject json = new JSONObject();

		try
		{
			json.put("manufacturer", Build.MANUFACTURER);
			json.put("model", Build.MODEL);
			json.put("osVersion", Build.VERSION.RELEASE);
			json.put("apiLevel", Build.VERSION.SDK_INT);
		}
		catch (JSONException e)
		{
			// Keys are constant and values are plain strings/ints, so this cannot happen in practice.
		}

		return json.toString();
	}

	// ---------------------------------------------------------------- storage

	/** directory is a mobiletools.StorageDirectory value: 0 internal, 1 app external, 2 shared. May return null. */
	@SuppressWarnings("deprecation")
	public static String getDirectory(int directory)
	{
		Context context = Extension.mainContext;

		if (context == null)
			return null;

		java.io.File file;

		switch (directory)
		{
			case 0:
				file = context.getFilesDir();
				break;
			case 1:
				// Null when no external storage is mounted; fall back to the always available internal folder.
				file = context.getExternalFilesDir(null);

				if (file == null)
					file = context.getFilesDir();

				break;
			default:
				file = Environment.getExternalStorageDirectory();
				break;
		}

		return file != null ? file.getAbsolutePath() : null;
	}

	// ---------------------------------------------------------------- haptics

	/** style is a mobiletools.ImpactStyle value: 0 light, 1 medium, 2 heavy, 3 soft, 4 rigid. */
	public static void impact(int style)
	{
		switch (style)
		{
			case 0:
				playEffect(VibrationEffect.EFFECT_TICK, 10, 60);
				break;
			case 2:
				playEffect(VibrationEffect.EFFECT_HEAVY_CLICK, 30, 255);
				break;
			case 3:
				playEffect(VibrationEffect.EFFECT_TICK, 15, 40);
				break;
			case 4:
				playEffect(VibrationEffect.EFFECT_CLICK, 12, 200);
				break;
			default:
				playEffect(VibrationEffect.EFFECT_CLICK, 20, 120);
				break;
		}
	}

	/** type is a mobiletools.NotificationType value: 0 success, 1 warning, 2 error. */
	public static void notification(int type)
	{
		// off/on/off/on... timings in ms, first entry is the initial delay
		switch (type)
		{
			case 1:
				playPattern(new long[] { 0, 40, 80, 40 });
				break;
			case 2:
				playPattern(new long[] { 0, 50, 60, 50, 60, 50 });
				break;
			default:
				playPattern(new long[] { 0, 30, 60, 30 });
				break;
		}
	}

	public static void selection()
	{
		playEffect(VibrationEffect.EFFECT_TICK, 8, 50);
	}

	/**
	 * Plays a custom pattern. data is "milliseconds:amplitude" pairs joined by commas, e.g. "0:0,30:255,60:0,30:120"
	 * (amplitude 0-255, 0 meaning off), as produced by HapticPattern.toWaveformString(). Replaces a running vibration.
	 * Malformed data is ignored rather than throwing, since it ultimately comes from mods.
	 */
	@SuppressWarnings("deprecation")
	public static void playWaveform(String data)
	{
		Vibrator vibrator = getVibrator();

		if (vibrator == null || !vibrator.hasVibrator() || data == null || data.length() == 0)
			return;

		String[] pairs = data.split(",");

		if (pairs.length == 0 || pairs.length > MAX_WAVEFORM_SEGMENTS)
			return;

		long[] timings = new long[pairs.length];
		int[] amplitudes = new int[pairs.length];

		try
		{
			for (int i = 0; i < pairs.length; i++)
			{
				String[] parts = pairs[i].split(":");
				timings[i] = Long.parseLong(parts[0]);
				amplitudes[i] = Integer.parseInt(parts[1]);

				if (timings[i] < 0 || amplitudes[i] < 0 || amplitudes[i] > 255)
					return;
			}
		}
		catch (NumberFormatException e)
		{
			return;
		}
		catch (ArrayIndexOutOfBoundsException e)
		{
			return;
		}

		vibrator.cancel();

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
		{
			// Without amplitude control a non-zero amplitude is not reliably honoured, so give it plain on/off timings.
			if (vibrator.hasAmplitudeControl())
				vibrator.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1));
			else
				vibrator.vibrate(VibrationEffect.createWaveform(onOffTimings(timings, amplitudes), -1));
		}
		else
		{
			vibrator.vibrate(onOffTimings(timings, amplitudes), -1);
		}
	}

	public static void cancelHaptics()
	{
		cancelVibration();
	}

	/** Bit field matching HapticCapabilitiesTools.fromBits(): 1 can vibrate, 2 amplitude control, 4 sharpness control (never here). */
	public static int getHapticCapabilities()
	{
		Vibrator vibrator = getVibrator();

		if (vibrator == null || !vibrator.hasVibrator())
			return 0;

		int bits = 1;

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && vibrator.hasAmplitudeControl())
			bits |= 2;

		return bits;
	}

	/** Turns segments with amplitudes into the off/on/off/on... timings the older vibrate(long[]) API expects. */
	private static long[] onOffTimings(long[] timings, int[] amplitudes)
	{
		ArrayList<Long> result = new ArrayList<Long>();
		boolean on = false;
		long current = 0;

		for (int i = 0; i < timings.length; i++)
		{
			boolean segmentOn = amplitudes[i] > 0;

			if (segmentOn == on)
			{
				current += timings[i];
			}
			else
			{
				result.add(current);
				current = timings[i];
				on = segmentOn;
			}
		}

		result.add(current);

		long[] array = new long[result.size()];

		for (int i = 0; i < array.length; i++)
			array[i] = result.get(i);

		return array;
	}

	/**
	 * Plays the system's predefined effect on Android 10+. Older versions get a short one-shot
	 * pulse of the given length and amplitude (1-255), or just the length before Android 8.
	 */
	@SuppressWarnings("deprecation")
	private static void playEffect(int predefinedEffect, long fallbackMilliseconds, int fallbackAmplitude)
	{
		Vibrator vibrator = getVibrator();

		if (vibrator == null || !vibrator.hasVibrator())
			return;

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
			vibrator.vibrate(VibrationEffect.createPredefined(predefinedEffect));
		else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			vibrator.vibrate(VibrationEffect.createOneShot(fallbackMilliseconds, fallbackAmplitude));
		else
			vibrator.vibrate(fallbackMilliseconds);
	}

	@SuppressWarnings("deprecation")
	private static void playPattern(long[] timings)
	{
		Vibrator vibrator = getVibrator();

		if (vibrator == null || !vibrator.hasVibrator())
			return;

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			vibrator.vibrate(VibrationEffect.createWaveform(timings, -1));
		else
			vibrator.vibrate(timings, -1);
	}

	// ---------------------------------------------------------------- file picker

	/**
	 * Opens the system document picker. extensions is comma separated without dots, empty for any file.
	 * Returns immediately; poll isFilePickerPending(), then read getPickedFile().
	 */
	public static boolean pickFile(String extensions)
	{
		final Activity activity = Extension.mainActivity;

		if (activity == null || pickPending)
			return false;

		pickPending = true;
		pickedPath = "";

		final String[] mimeTypes = mimeTypesFor(extensions);

		activity.runOnUiThread(new Runnable()
		{
			@Override
			public void run()
			{
				// ACTION_OPEN_DOCUMENT reaches every provider (Downloads, Drive, SD cards); GET_CONTENT is the fallback.
				for (String action : new String[] { Intent.ACTION_OPEN_DOCUMENT, Intent.ACTION_GET_CONTENT })
				{
					Intent intent = new Intent(action);
					intent.addCategory(Intent.CATEGORY_OPENABLE);
					intent.setType(mimeTypes.length == 1 ? mimeTypes[0] : "*/*");

					if (mimeTypes.length > 1)
						intent.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes);

					try
					{
						activity.startActivityForResult(intent, PICK_FILE_REQUEST_CODE);
						return;
					}
					catch (ActivityNotFoundException e)
					{
						// Try the next action.
					}
				}

				pickPending = false;
			}
		});

		return true;
	}

	public static boolean isFilePickerPending()
	{
		return pickPending;
	}

	public static String getPickedFile()
	{
		return pickedPath;
	}

	/** MIME types the picker should offer for the extensions, or the single wildcard type when any file is fine. */
	private static String[] mimeTypesFor(String extensions)
	{
		if (extensions == null || extensions.length() == 0)
			return new String[] { "*/*" };

		ArrayList<String> types = new ArrayList<String>();

		for (String extension : extensions.split(","))
		{
			String type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);

			// An extension Android doesn't know can't be filtered on.
			if (type == null)
				return new String[] { "*/*" };

			types.add(type);

			// Zip files show up under several names depending on where they were downloaded from.
			if ("zip".equals(extension))
			{
				types.add("application/x-zip-compressed");
				types.add("application/x-zip");
			}
		}

		// Many providers label files they don't recognise as plain bytes, which would hide them otherwise.
		types.add("application/octet-stream");

		return types.toArray(new String[0]);
	}

	/** Copies what the picker returned into the cache, off the UI thread since it may be large or remote. */
	private static void finishPick(final Uri uri)
	{
		new Thread(new Runnable()
		{
			@Override
			public void run()
			{
				String path = "";

				try
				{
					path = copyToCache(uri);
				}
				catch (Exception e)
				{
					// Unreadable or vanished file: report it as no file.
				}

				pickedPath = path;
				pickPending = false;
			}
		}).start();
	}

	private static String copyToCache(Uri uri) throws IOException
	{
		Context context = Extension.mainContext;

		if (context == null)
			return "";

		File folder = new File(context.getCacheDir(), PICKED_FOLDER);

		// Only the latest pick is kept, so the cache doesn't fill up with old copies.
		File[] old = folder.listFiles();

		if (old != null)
		{
			for (File file : old)
				file.delete();
		}

		if (!folder.isDirectory() && !folder.mkdirs())
			return "";

		File target = new File(folder, safeFileName(displayName(context, uri)));
		InputStream input = context.getContentResolver().openInputStream(uri);

		if (input == null)
			return "";

		OutputStream output = new FileOutputStream(target);

		try
		{
			byte[] buffer = new byte[64 * 1024];
			int read;

			while ((read = input.read(buffer)) != -1)
				output.write(buffer, 0, read);
		}
		finally
		{
			input.close();
			output.close();
		}

		return target.getAbsolutePath();
	}

	private static String displayName(Context context, Uri uri)
	{
		Cursor cursor = null;

		try
		{
			cursor = context.getContentResolver().query(uri, new String[] { OpenableColumns.DISPLAY_NAME }, null, null, null);

			if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0))
				return cursor.getString(0);
		}
		catch (Exception e)
		{
			// Some providers don't support the query, the last path segment will do.
		}
		finally
		{
			if (cursor != null)
				cursor.close();
		}

		return uri.getLastPathSegment();
	}

	/** The name comes from another app, so keep only characters that are harmless in a path. */
	private static String safeFileName(String name)
	{
		if (name != null)
		{
			int slash = name.lastIndexOf('/');

			if (slash >= 0)
				name = name.substring(slash + 1);

			name = name.replaceAll("[^A-Za-z0-9._ -]", "_").trim();
		}

		if (name == null || name.length() == 0 || name.startsWith("."))
			name = "picked" + (name != null ? name : "");

		return name.length() > 120 ? name.substring(name.length() - 120) : name;
	}

	// ---------------------------------------------------------------- permissions

	/** Returns a mobiletools.PermissionStatus value for the permission id (see mobiletools.Permission). */
	public static int checkPermission(String id)
	{
		Activity activity = Extension.mainActivity;

		SettingsPermission settings = findSettingsPermission(id);

		if (settings != null)
			return checkSettingsPermission(settings);

		if ("biometrics".equals(id))
			return checkBiometrics();

		String[] permissions = androidPermissions(id);

		// No runtime permission on this OS version (or unknown id): nothing to ask.
		if (permissions.length == 0 || Build.VERSION.SDK_INT < Build.VERSION_CODES.M)
			return STATUS_GRANTED;

		if (activity == null)
			return STATUS_NOT_DETERMINED;

		// Granting any of the group is enough, e.g. approximate location only.
		for (String permission : permissions)
		{
			if (activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED)
				return STATUS_GRANTED;
		}

		// Android can't tell "never asked" from "don't ask again", so remember if we asked.
		if (!wasRequested(id))
			return STATUS_NOT_DETERMINED;

		for (String permission : permissions)
		{
			if (activity.shouldShowRequestPermissionRationale(permission))
				return STATUS_DENIED;
		}

		return STATUS_DENIED_PERMANENTLY;
	}

	/**
	 * Shows the system prompt. Returns immediately; poll isPermissionRequestPending().
	 * Does nothing when the permission is already granted or no prompt is possible.
	 */
	public static void requestPermission(final String id)
	{
		final Activity activity = Extension.mainActivity;
		final String[] permissions = androidPermissions(id);

		SettingsPermission settings = findSettingsPermission(id);

		if (settings != null)
		{
			requestSettingsPermission(activity, settings);
			return;
		}

		if (activity == null || permissions.length == 0 || Build.VERSION.SDK_INT < Build.VERSION_CODES.M)
			return;

		// From Android 11 background location can only be requested once foreground location is granted.
		if ("location_always".equals(id) && Build.VERSION.SDK_INT >= 30 && checkPermission("location") != STATUS_GRANTED)
			return;

		if (checkPermission(id) == STATUS_GRANTED || !pendingRequests.add(id))
			return;

		activity.runOnUiThread(new Runnable()
		{
			@Override
			public void run()
			{
				activity.requestPermissions(permissions, PERMISSION_REQUEST_CODE);
			}
		});
	}

	public static boolean isPermissionRequestPending(String id)
	{
		return pendingRequests.contains(id);
	}

	/** Opens this app's page in the system settings. */
	public static void openSettings()
	{
		Activity activity = Extension.mainActivity;

		if (activity == null)
			return;

		Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.getPackageName(), null));
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
		activity.startActivity(intent);
	}

	/**
	 * Biometrics have no runtime permission, so report whether they are usable instead.
	 * requestPermission() does nothing for them because androidPermissions() is empty.
	 */
	private static int checkBiometrics()
	{
		Activity activity = Extension.mainActivity;

		if (activity == null)
			return STATUS_NOT_DETERMINED;

		// android.hardware.biometrics arrived in Android 9; Android 9 itself can only tell us about fingerprints.
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P)
			return STATUS_RESTRICTED;

		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q)
			return activity.getPackageManager().hasSystemFeature(PackageManager.FEATURE_FINGERPRINT) ? STATUS_GRANTED : STATUS_RESTRICTED;

		BiometricManager manager = activity.getSystemService(BiometricManager.class);

		if (manager == null)
			return STATUS_RESTRICTED;

		int result;

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
			result = manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK);
		else
			result = legacyCanAuthenticate(manager);

		switch (result)
		{
			case BiometricManager.BIOMETRIC_SUCCESS:
				return STATUS_GRANTED;
			case BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED:
			case BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE:
				return STATUS_DENIED;
			default:
				return STATUS_RESTRICTED;
		}
	}

	@SuppressWarnings("deprecation")
	private static int legacyCanAuthenticate(BiometricManager manager)
	{
		return manager.canAuthenticate();
	}

	/**
	 * Permissions the user grants on a system settings screen rather than in a dialog.
	 * They are only "special" from the Android version in minSdk on; before that the permission
	 * either doesn't exist (granted) or is a regular runtime permission, see androidPermissions().
	 */
	private static final class SettingsPermission
	{
		final String id;
		final int minSdk;
		final String action;
		final String fallbackAction;
		final int requestCode;

		SettingsPermission(String id, int minSdk, String action, String fallbackAction, int requestCode)
		{
			this.id = id;
			this.minSdk = minSdk;
			this.action = action;
			this.fallbackAction = fallbackAction;
			this.requestCode = requestCode;
		}
	}

	// Action names are written out so this still compiles against an older Android SDK than the one that added them.
	private static final SettingsPermission[] SETTINGS_PERMISSIONS = {
		new SettingsPermission("external_storage", 30, "android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION", "android.settings.MANAGE_ALL_FILES_ACCESS_PERMISSION", 7392),
		new SettingsPermission("overlay", 23, "android.settings.action.MANAGE_OVERLAY_PERMISSION", null, 7393),
		new SettingsPermission("ignore_battery_optimizations", 23, "android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", null, 7394),
		new SettingsPermission("exact_alarm", 31, "android.settings.REQUEST_SCHEDULE_EXACT_ALARM", null, 7395),
		new SettingsPermission("write_settings", 23, "android.settings.action.MANAGE_WRITE_SETTINGS", null, 7396),
		new SettingsPermission("install_packages", 26, "android.settings.MANAGE_UNKNOWN_APP_SOURCES", null, 7397)
	};

	/** The settings screen permission for id on this Android version, or null if id is a regular permission here. */
	private static SettingsPermission findSettingsPermission(String id)
	{
		for (SettingsPermission permission : SETTINGS_PERMISSIONS)
		{
			if (permission.id.equals(id) && Build.VERSION.SDK_INT >= permission.minSdk)
				return permission;
		}

		return null;
	}

	private static int checkSettingsPermission(SettingsPermission permission)
	{
		Context context = Extension.mainContext;

		if (context == null)
			return STATUS_NOT_DETERMINED;

		boolean granted = false;

		switch (permission.id)
		{
			case "external_storage":
				granted = Environment.isExternalStorageManager();
				break;

			case "overlay":
				granted = Settings.canDrawOverlays(context);
				break;

			case "ignore_battery_optimizations":
			{
				PowerManager power = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
				granted = power != null && power.isIgnoringBatteryOptimizations(context.getPackageName());
				break;
			}

			case "exact_alarm":
			{
				AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
				granted = alarms != null && alarms.canScheduleExactAlarms();
				break;
			}

			case "write_settings":
				granted = Settings.System.canWrite(context);
				break;

			case "install_packages":
				granted = context.getPackageManager().canRequestPackageInstalls();
				break;
		}

		if (granted)
			return STATUS_GRANTED;

		// The screen can always be opened again, so a refusal is never permanent.
		return wasRequested(permission.id) ? STATUS_DENIED : STATUS_NOT_DETERMINED;
	}

	private static void requestSettingsPermission(final Activity activity, final SettingsPermission permission)
	{
		if (activity == null || checkSettingsPermission(permission) == STATUS_GRANTED || !pendingRequests.add(permission.id))
			return;

		activity.runOnUiThread(new Runnable()
		{
			@Override
			public void run()
			{
				Uri packageUri = Uri.parse("package:" + activity.getPackageName());

				try
				{
					activity.startActivityForResult(new Intent(permission.action, packageUri), permission.requestCode);
					return;
				}
				catch (ActivityNotFoundException e)
				{
					// Some devices lack the per-app screen, try the next best thing below.
				}

				try
				{
					Intent fallback = permission.fallbackAction != null
						? new Intent(permission.fallbackAction)
						: new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri);

					activity.startActivityForResult(fallback, permission.requestCode);
				}
				catch (ActivityNotFoundException e)
				{
					pendingRequests.remove(permission.id);
				}
			}
		});
	}

	/** Called when the user comes back from one of the settings screens above, or from the file picker. */
	@Override
	public boolean onActivityResult(int requestCode, int resultCode, Intent data)
	{
		if (requestCode == PICK_FILE_REQUEST_CODE)
		{
			if (resultCode == Activity.RESULT_OK && data != null && data.getData() != null)
				finishPick(data.getData());
			else
				pickPending = false;

			return true;
		}

		for (SettingsPermission permission : SETTINGS_PERMISSIONS)
		{
			if (permission.requestCode == requestCode)
			{
				markRequested(permission.id);
				pendingRequests.remove(permission.id);
			}
		}

		return true;
	}

	@Override
	public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults)
	{
		if (requestCode != PERMISSION_REQUEST_CODE)
			return true;

		// Empty arrays mean the request was interrupted. Release everything so Haxe doesn't wait forever.
		if (permissions.length == 0)
		{
			synchronized (pendingRequests)
			{
				for (String id : new HashSet<String>(pendingRequests))
				{
					if (findSettingsPermission(id) == null)
						pendingRequests.remove(id);
				}
			}

			return true;
		}

		synchronized (pendingRequests)
		{
			for (String id : new HashSet<String>(pendingRequests))
			{
				// Settings-based requests finish in onActivityResult, never here.
				if (findSettingsPermission(id) != null)
					continue;

				for (String permission : androidPermissions(id))
				{
					if (contains(permissions, permission))
					{
						markRequested(id);
						pendingRequests.remove(id);
						break;
					}
				}
			}
		}

		return true;
	}

	/** Maps a mobiletools.Permission id to the Android permissions to request. Empty = nothing to ask. */
	private static String[] androidPermissions(String id)
	{
		if (id == null)
			return new String[0];

		switch (id)
		{
			case "camera":
				return new String[] { "android.permission.CAMERA" };

			case "microphone":
				return new String[] { "android.permission.RECORD_AUDIO" };

			case "location":
				return new String[] { "android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION" };

			case "notifications":
				// Runtime permission only exists from Android 13 (API 33).
				return Build.VERSION.SDK_INT >= 33 ? new String[] { "android.permission.POST_NOTIFICATIONS" } : new String[0];

			case "images":
				return Build.VERSION.SDK_INT >= 33
					? new String[] { "android.permission.READ_MEDIA_IMAGES" }
					: new String[] { "android.permission.READ_EXTERNAL_STORAGE" };

			case "audio":
				return Build.VERSION.SDK_INT >= 33
					? new String[] { "android.permission.READ_MEDIA_AUDIO" }
					: new String[] { "android.permission.READ_EXTERNAL_STORAGE" };

			case "video":
				return Build.VERSION.SDK_INT >= 33
					? new String[] { "android.permission.READ_MEDIA_VIDEO" }
					: new String[] { "android.permission.READ_EXTERNAL_STORAGE" };

			case "bluetooth":
				// Before Android 12 Bluetooth permissions are install-time only.
				return Build.VERSION.SDK_INT >= 31
					? new String[] { "android.permission.BLUETOOTH_CONNECT", "android.permission.BLUETOOTH_SCAN" }
					: new String[0];

			case "location_always":
				// Background location is a separate permission from Android 10. Before that, foreground access already covers it.
				return Build.VERSION.SDK_INT >= 29
					? new String[] { "android.permission.ACCESS_BACKGROUND_LOCATION" }
					: new String[] { "android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION" };

			case "phone":
				return new String[] { "android.permission.READ_PHONE_STATE" };

			case "nearby_wifi":
				// Introduced in Android 13; before that, scanning Wi-Fi was covered by the location permission.
				return Build.VERSION.SDK_INT >= 33 ? new String[] { "android.permission.NEARBY_WIFI_DEVICES" } : new String[0];

			case "body_sensors":
				return new String[] { "android.permission.BODY_SENSORS" };

			case "contacts":
				return new String[] { "android.permission.READ_CONTACTS" };

			case "calendar":
				return new String[] { "android.permission.READ_CALENDAR", "android.permission.WRITE_CALENDAR" };

			case "motion":
				// Activity recognition became a runtime permission in Android 10.
				return Build.VERSION.SDK_INT >= 29 ? new String[] { "android.permission.ACTIVITY_RECOGNITION" } : new String[0];

			case "storage":
				// Has no effect from Android 13, where media access moved to READ_MEDIA_*.
				return Build.VERSION.SDK_INT >= 33
					? new String[0]
					: new String[] { "android.permission.READ_EXTERNAL_STORAGE", "android.permission.WRITE_EXTERNAL_STORAGE" };

			case "external_storage":
				// Android 11+ uses "All files access" instead, see SETTINGS_PERMISSIONS.
				return new String[] { "android.permission.READ_EXTERNAL_STORAGE", "android.permission.WRITE_EXTERNAL_STORAGE" };

			default:
				return new String[0];
		}
	}

	private static boolean contains(String[] values, String value)
	{
		for (String v : values)
		{
			if (v.equals(value))
				return true;
		}

		return false;
	}

	private static boolean wasRequested(String id)
	{
		SharedPreferences prefs = getPreferences();
		return prefs != null && prefs.getBoolean(id, false);
	}

	private static void markRequested(String id)
	{
		SharedPreferences prefs = getPreferences();

		if (prefs != null)
			prefs.edit().putBoolean(id, true).apply();
	}

	private static SharedPreferences getPreferences()
	{
		Context context = Extension.mainContext;
		return context == null ? null : context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
	}

	@SuppressWarnings("deprecation")
	private static Vibrator getVibrator()
	{
		Context context = Extension.mainContext;

		if (context == null)
			return null;

		return (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
	}
}
