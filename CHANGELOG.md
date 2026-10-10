# Changelog

## 0.1.0

- Initial release.
- `MobileTools`: `showToast`, `vibrate`, `cancelVibration`, `setKeepScreenOn`, `getDeviceInfo`, `getDirectory` (`INTERNAL`, `APP_EXTERNAL`, `SHARED`).
- `Permissions`: `check`, `request`, `requestMany`, `openSettings` for `CAMERA`, `MICROPHONE`, `LOCATION`, `NOTIFICATIONS`, `IMAGES`, `VIDEO`, `AUDIO`, `STORAGE`, `EXTERNAL_STORAGE`, `BLUETOOTH`, `CONTACTS`, `CALENDAR`, `MOTION` and `BIOMETRICS` (availability only).
- `Haptics`: `impact`, `notification`, `selection`.
- Scripting: `Script` runs hscript in a sandbox that only creates allow-listed classes and only sees what it is given (`mobile`, `Std`, `Math`, `StringTools`, `Json`).
- Modding: `ModManager` finds mods (`mod.json` + scripts + files), handles dependencies, order and persisted state, serves files by priority, and runs script hooks (`onLoad`, `onUnload`, `onUpdate`, your own). `useSharedStorage()` ties it to `EXTERNAL_STORAGE`.
- Android backend (Java + JNI), iOS backend (Objective-C++ compiled by hxcpp) and a no-op `NullBackend` for every other target.
- `samples/showcase`: touch UI app covering every feature.
- `tests/`: scripting, sandbox and mod system tests.
