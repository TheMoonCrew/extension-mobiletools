package mobiletools;

import mobiletools.ImpactStyle;
import mobiletools.NotificationType;

/**
 * Short, semantic haptic feedback for UI interactions.
 *
 * Unlike `MobileTools.vibrate()`, which runs for a fixed time, these describe
 * *what happened* and let each platform pick the best feel:
 * - iOS uses the Taptic Engine feedback generators.
 * - Android uses the predefined vibration effects (API 29+) and falls back to short pulses.
 *
 * On targets without haptics every call is a no-op.
 *
 * ```haxe
 * Haptics.selection();              // scrolling a picker, toggling a switch
 * Haptics.impact(MEDIUM);           // a button press, a collision
 * Haptics.notification(SUCCESS);    // a task finished
 * ```
 */
class Haptics
{
	/** Plays a tap of the given strength. */
	public static function impact(style:ImpactStyle = MEDIUM):Void
	{
		MobileTools.backend.impact(style);
	}

	/** Plays a pattern that tells the user a task succeeded, needs attention, or failed. */
	public static function notification(type:NotificationType):Void
	{
		MobileTools.backend.notification(type);
	}

	/** Plays a very light tick, meant for changes in a selection. */
	public static function selection():Void
	{
		MobileTools.backend.selection();
	}
}
