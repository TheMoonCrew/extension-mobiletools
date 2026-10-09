package mobiletools;

/**
 * Strength of a physical-feeling tap played by `Haptics.impact()`.
 *
 * The values are shared with the native backends, so they must not change.
 */
enum abstract ImpactStyle(Int) to Int
{
	var LIGHT = 0;
	var MEDIUM = 1;
	var HEAVY = 2;

	/** A softer, more cushioned tap. Falls back to `LIGHT` on iOS older than 13. */
	var SOFT = 3;

	/** A sharper, more rigid tap. Falls back to `HEAVY` on iOS older than 13. */
	var RIGID = 4;
}
