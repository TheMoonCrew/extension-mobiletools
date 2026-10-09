package mobiletools;

/**
 * Outcome communicated by `Haptics.notification()`.
 *
 * The values are shared with the native backends, so they must not change.
 */
enum abstract NotificationType(Int) to Int
{
	var SUCCESS = 0;
	var WARNING = 1;
	var ERROR = 2;
}
