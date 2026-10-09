#ifndef MOBILETOOLS_IOS_H
#define MOBILETOOLS_IOS_H

// Plain C++ interface: this header is included from hxcpp generated code, so it must not contain Objective-C.
// Implemented in MobileToolsIOS.mm. Signatures must stay in sync with IOSNative.hx.

namespace mobiletools
{
	namespace ios
	{
		void showToast(const char* message, int duration);
		void vibrate();
		void setKeepScreenOn(bool enabled);

		// JSON matching the mobiletools.DeviceInfo typedef. The pointer stays valid until the next call.
		const char* getDeviceInfo();

		// Returns a mobiletools.PermissionStatus value for the permission id (see mobiletools.Permission).
		int checkPermission(const char* permission);
		void requestPermission(const char* permission);
		bool isPermissionRequestPending(const char* permission);
		void openSettings();
	}
}

#endif
