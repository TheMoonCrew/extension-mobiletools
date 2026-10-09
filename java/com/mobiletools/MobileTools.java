package com.mobiletools;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.Settings;
import android.view.WindowManager;
import android.widget.Toast;

import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

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

	private static final int PERMISSION_REQUEST_CODE = 7391;
	private static final String PREFS_NAME = "mobiletools_permissions";

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

	// ---------------------------------------------------------------- permissions

	/** Returns a mobiletools.PermissionStatus value for the permission id (see mobiletools.Permission). */
	public static int checkPermission(String id)
	{
		Activity activity = Extension.mainActivity;
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

		if (activity == null || permissions.length == 0 || Build.VERSION.SDK_INT < Build.VERSION_CODES.M)
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

	@Override
	public boolean onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults)
	{
		if (requestCode != PERMISSION_REQUEST_CODE)
			return true;

		// Empty arrays mean the request was interrupted. Release everything so Haxe doesn't wait forever.
		if (permissions.length == 0)
		{
			pendingRequests.clear();
			return true;
		}

		synchronized (pendingRequests)
		{
			for (String id : new HashSet<String>(pendingRequests))
			{
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

			case "photos":
				return Build.VERSION.SDK_INT >= 33
					? new String[] { "android.permission.READ_MEDIA_IMAGES" }
					: new String[] { "android.permission.READ_EXTERNAL_STORAGE" };

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
