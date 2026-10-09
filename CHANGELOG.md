# Changelog

## 0.1.0

- Initial release.
- `MobileTools`: `showToast`, `vibrate`, `cancelVibration`, `setKeepScreenOn`, `getDeviceInfo`.
- `Permissions`: `check`, `request`, `requestMany`, `openSettings` for `CAMERA`, `MICROPHONE`, `LOCATION`, `NOTIFICATIONS` and `PHOTOS`.
- `Haptics`: `impact`, `notification`, `selection`.
- Android backend (Java + JNI), iOS backend (Objective-C++ compiled by hxcpp) and a no-op `NullBackend` for every other target.
