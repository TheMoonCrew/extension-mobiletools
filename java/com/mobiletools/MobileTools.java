package com.mobiletools;

import android.app.Activity;
import android.content.Context;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.WindowManager;
import android.widget.Toast;

import org.haxe.extension.Extension;
import org.json.JSONException;
import org.json.JSONObject;

/**
 * Native side of extension-mobiletools. Every public static method is called from
 * Haxe through JNI (see AndroidBackend.hx), so signatures must stay in sync.
 */
public class MobileTools extends Extension
{
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

	@SuppressWarnings("deprecation")
	private static Vibrator getVibrator()
	{
		Context context = Extension.mainContext;

		if (context == null)
			return null;

		return (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
	}
}
