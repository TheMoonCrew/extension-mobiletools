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

		// Hides the status bar and home indicator, see MobileTools.setFullscreen().
		void setFullscreen(bool enabled);

		// "top,right,bottom,left" in pixels. The pointer stays valid until the next call.
		const char* getSafeArea();

		// JSON matching the mobiletools.DeviceInfo typedef. The pointer stays valid until the next call.
		const char* getDeviceInfo();

		// directory: mobiletools.StorageDirectory. The pointer stays valid until the next call.
		const char* getDirectory(int directory);

		// events: "time:duration:intensity:sharpness" per event joined by commas, see HapticPattern.toCompact().
		// Replaces a pattern that is still playing. getHapticCapabilities() returns the bits 1 can vibrate,
		// 2 amplitude control, 4 sharpness control.
		void playHapticPattern(const char* events);
		void cancelHaptics();
		int getHapticCapabilities();

		// style: mobiletools.ImpactStyle, type: mobiletools.NotificationType
		void impact(int style);
		void notification(int type);
		void selection();

		// Returns a mobiletools.PermissionStatus value for the permission id (see mobiletools.Permission).
		int checkPermission(const char* permission);
		void requestPermission(const char* permission);
		bool isPermissionRequestPending(const char* permission);
		void openSettings();

		// extensions: comma separated, without dots, empty for any file. Returns false if no picker could be shown.
		// getPickedFile() is a private copy of the chosen file, or "" when cancelled. Its pointer stays valid until the next call.
		bool pickFile(const char* extensions);
		bool isFilePickerPending();
		const char* getPickedFile();
	}
}

#endif
