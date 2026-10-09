package mobiletools;

import haxe.Timer;
import mobiletools.Permission;
import mobiletools.PermissionStatus;

/**
 * Cross-platform runtime permissions.
 *
 * Works the same on Android and iOS. On targets without a runtime permission
 * model (desktop, html5) every permission is reported as `GRANTED`.
 *
 * ```haxe
 * Permissions.request(CAMERA, function(status)
 * {
 *     if (status.isGranted())
 *         startCamera();
 *     else if (status == DENIED_PERMANENTLY)
 *         Permissions.openSettings();
 * });
 * ```
 */
class Permissions
{
	/** How often pending requests are checked for a result, in milliseconds. */
	private static inline var POLL_INTERVAL:Int = 100;

	private static var pending:Array<PendingRequest> = [];
	private static var timer:Timer;

	/** Returns the current status of `permission` without showing any prompt. */
	public static function check(permission:Permission):PermissionStatus
	{
		return MobileTools.backend.checkPermission(permission);
	}

	/**
	 * Requests `permission`, showing the system prompt if the OS still allows it.
	 *
	 * `callback` receives the final status. It runs on the main thread, and runs
	 * immediately (before this function returns) when no prompt is needed, e.g.
	 * the permission is already granted or permanently denied.
	 */
	public static function request(permission:Permission, ?callback:PermissionStatus->Void):Void
	{
		var backend = MobileTools.backend;

		if (!backend.isPermissionRequestPending(permission))
		{
			var status = backend.checkPermission(permission);

			if (!status.canRequest())
			{
				finish(callback, status);
				return;
			}

			backend.requestPermission(permission);
		}

		// The native side did not start a prompt (e.g. no activity yet): report what we have.
		if (!backend.isPermissionRequestPending(permission))
		{
			finish(callback, backend.checkPermission(permission));
			return;
		}

		pending.push({permission: permission, callback: callback});
		startPolling();
	}

	/**
	 * Requests several permissions at once.
	 *
	 * `callback` is called once every request has finished, with the statuses
	 * in the same order as `permissions`.
	 */
	public static function requestMany(permissions:Array<Permission>, callback:Array<PermissionStatus>->Void):Void
	{
		if (permissions == null || permissions.length == 0)
		{
			if (callback != null)
				callback([]);
			return;
		}

		var results:Array<PermissionStatus> = [for (_ in permissions) NOT_DETERMINED];
		var remaining = permissions.length;

		for (i in 0...permissions.length)
		{
			request(permissions[i], function(status)
			{
				results[i] = status;

				if (--remaining == 0 && callback != null)
					callback(results);
			});
		}
	}

	/** Opens the system settings page of this app, where the user can change permissions. */
	public static function openSettings():Void
	{
		MobileTools.backend.openSettings();
	}

	private static function startPolling():Void
	{
		if (timer != null)
			return;

		timer = new Timer(POLL_INTERVAL);
		timer.run = poll;
	}

	private static function stopPolling():Void
	{
		if (timer == null)
			return;

		timer.stop();
		timer = null;
	}

	private static function poll():Void
	{
		var backend = MobileTools.backend;

		for (request in pending.copy())
		{
			if (backend.isPermissionRequestPending(request.permission))
				continue;

			pending.remove(request);
			finish(request.callback, backend.checkPermission(request.permission));
		}

		// A callback may have queued new requests, so only stop when really idle.
		if (pending.length == 0)
			stopPolling();
	}

	private static inline function finish(callback:PermissionStatus->Void, status:PermissionStatus):Void
	{
		if (callback != null)
			callback(status);
	}
}

private typedef PendingRequest =
{
	var permission:Permission;
	var callback:PermissionStatus->Void;
}
