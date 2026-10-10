# Changelog

## 0.1.0

- Initial release.
- `MobileTools`: `showToast`, `vibrate`, `cancelVibration`, `setKeepScreenOn`, `getDeviceInfo`, `getDirectory` (`INTERNAL`, `APP_EXTERNAL`, `SHARED`).
- `Permissions`: `check`, `request`, `requestMany`, `openSettings` for `CAMERA`, `MICROPHONE`, `LOCATION`, `NOTIFICATIONS`, `IMAGES`, `VIDEO`, `AUDIO`, `STORAGE`, `EXTERNAL_STORAGE`, `BLUETOOTH`, `CONTACTS`, `CALENDAR`, `MOTION`, `BIOMETRICS` (availability only), `LOCATION_ALWAYS`, `TRACKING`, `PHONE`, `NEARBY_WIFI`, `BODY_SENSORS`, `OVERLAY`, `IGNORE_BATTERY_OPTIMIZATIONS`, `EXACT_ALARM`, `WRITE_SETTINGS` and `INSTALL_PACKAGES`. Permissions granted on a system settings screen share one mechanism on Android.
- `Haptics`: `impact`, `notification`, `selection`, plus custom `HapticPattern`s (events with time, duration, intensity and sharpness; builder, JSON, limits), 11 built in presets, a layered pattern library (`register`, `playNamed`), `capabilities`, and the user's `enabled` and `intensity` settings. Core Haptics on iOS (impact generators as fallback), amplitude waveforms on Android (on/off as fallback).
- Scripting: `Script` runs hscript in a sandbox that only creates allow-listed classes and only sees what it is given (`mobile`, `haptics`, `Std`, `Math`, `StringTools`, `Json`). `haptics` plays and builds patterns, and can `define()` them per mod.
- Modding: `ModManager` finds mods (`mod.json` + scripts + files), handles dependencies, order and persisted state, serves files by priority, and runs script hooks (`onLoad`, `onUnload`, `onUpdate`, your own). Mods can ship haptic patterns in `haptics/*.json`, which override built in ones while enabled. `useSharedStorage()` ties it to `EXTERNAL_STORAGE`.
- Android backend (Java + JNI), iOS backend (Objective-C++ compiled by hxcpp) and a no-op `NullBackend` for every other target.
- `samples/showcase`: touch UI app covering every feature.
- `tests/`: 278 checks for scripting, the sandbox, mods and haptics.
