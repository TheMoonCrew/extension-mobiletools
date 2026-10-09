# Changelog

## 0.2.0

- iOS backend (Objective-C++ compiled by hxcpp): toast overlay, vibration, keep screen on, device info.
- Cross-platform runtime permissions: `Permissions.check/request/requestMany/openSettings` for `CAMERA`, `MICROPHONE`, `LOCATION`, `NOTIFICATIONS` and `PHOTOS`.
- `IBackend` gained `checkPermission`, `requestPermission`, `isPermissionRequestPending` and `openSettings`.

## 0.1.0

- Initial base of the library.
- `MobileTools` API: `showToast`, `vibrate`, `cancelVibration`, `setKeepScreenOn`, `getDeviceInfo`.
- Android backend (Java + JNI) and no-op `NullBackend` for every other target.
