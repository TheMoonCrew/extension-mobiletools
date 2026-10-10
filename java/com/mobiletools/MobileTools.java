package com.mobiletools;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.hardware.biometrics.BiometricManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
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
	private static final int STATUS_RESTRICTED = 4;

	private static final int PERMISSION_REQUEST_CODE = 7391;
	private static final int ALL_FILES_REQUEST_CODE = 7392;
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

		if (usesAllFilesAccess(id))
			return checkAllFilesAccess();

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

		if (usesAllFilesAccess(id))
		{
			requestAllFilesAccess(activity);
			return;
		}

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

	/** "All files access" (Android 11+) is a settings switch rather than a runtime permission. */
	private static boolean usesAllFilesAccess(String id)
	{
		return "external_storage".equals(id) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R;
	}

	private static int checkAllFilesAccess()
	{
		if (Environment.isExternalStorageManager())
			return STATUS_GRANTED;

		// The screen can always be opened again, so a refusal is never permanent.
		return wasRequested("external_storage") ? STATUS_DENIED : STATUS_NOT_DETERMINED;
	}

	private static void requestAllFilesAccess(final Activity activity)
	{
		if (activity == null || checkAllFilesAccess() == STATUS_GRANTED || !pendingRequests.add("external_storage"))
			return;

		activity.runOnUiThread(new Runnable()
		{
			@Override
			public void run()
			{
				Uri packageUri = Uri.parse("package:" + activity.getPackageName());

				try
				{
					activity.startActivityForResult(new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, packageUri), ALL_FILES_REQUEST_CODE);
				}
				catch (ActivityNotFoundException e)
				{
					// Some devices lack the per-app screen, so fall back to the list of all apps.
					try
					{
						activity.startActivityForResult(new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION), ALL_FILES_REQUEST_CODE);
					}
					catch (ActivityNotFoundException e2)
					{
						pendingRequests.remove("external_storage");
					}
				}
			}
		});
	}

	/** Called when the user comes back from the "All files access" settings screen. */
	@Override
	public boolean onActivityResult(int requestCode, int resultCode, Intent data)
	{
		if (requestCode == ALL_FILES_REQUEST_CODE)
		{
			markRequested("external_storage");
			pendingRequests.remove("external_storage");
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
					if (!usesAllFilesAccess(id))
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
				if (usesAllFilesAccess(id))
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
				// Android 11+ uses "All files access" instead, see usesAllFilesAccess().
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
