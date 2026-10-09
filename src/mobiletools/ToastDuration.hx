package mobiletools;

/**
 * How long a toast message stays on screen.
 */
enum abstract ToastDuration(Int) to Int
{
	var SHORT = 0;
	var LONG = 1;
}
