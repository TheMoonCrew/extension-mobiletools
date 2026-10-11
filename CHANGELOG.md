# Changelog

## 0.2.0

- `MobileTools.setFullscreen()` / `isFullscreen`: immersive mode on Android (bars hidden, swipe to peek, drawn next to the notch on Android 9+, applied again after the app or a dialog gives focus back), hidden status bar, auto-hidden home indicator and deferred edge swipes on iOS.
- `MobileTools.getSafeArea()`: pixels on each edge covered by notches, camera holes, rounded corners (iOS) and visible system bars, measured against the game's view.
- `FilePicker.pick()`: the system file picker (document picker on Android, Files on iOS), handing back a private copy of the chosen file. No permission needed.
- Modding on phones:
  - `ModManager.install()` installs a mod from a `.zip`, or updates it where it already is. Nothing changes unless the whole archive is valid. It refuses paths leaving the mod folder, symbolic links, archives over `maxInstallSize` / `maxInstallFiles` (checked before anything is decompressed), data that doesn't match its declared size or CRC, encrypted and ZIP64 archives, and target folders that already hold something else.
  - `ModManager.importFromDevice()` picks a zip with the file picker and installs it.
  - `ModManager.uninstall()` disables a mod (and its dependents) and deletes its folder without following symbolic links.
  - `platforms` in `mod.json` (`android`, `ios`, `mobile`, `desktop`, `html5`), with `ModManager.platform` to override the platform checked against.
  - `onPause`, `onResume` and `onResize(width, height)` script hooks, connected to Lime's window events (`ModManager.followAppEvents`), or called with `pause()`, `resume()` and `resize()`.
  - Hidden folders in a mods root are skipped when scanning.
- Scripts: `mobile.isFullscreen()`, `mobile.getSafeArea()` and `mobile.platform`.
- Fixed: on C++ (Android, iOS) errors in script functions, such as an unknown variable or a class scripts may not create, were swallowed and the function returned `null`. hxcpp lets hscript's `catch (e:Stop)` catch any enum. `ScriptInterp` now rethrows everything that isn't control flow, and `include.xml` defines `hscriptPos` so errors inside loops are reported too.
- Fixed: on C++ a host function exposed to scripts that threw an enum (such as `haxe.io.Error`) crashed the app, because `Script` printed it as an hscript error.
- `IBackend` gained `setFullscreen`, `getSafeArea`, `pickFile`, `isFilePickerPending` and `getPickedFile`. Custom backends extending `NullBackend` keep working.
- iOS now links `MobileCoreServices.framework`.
- `samples/showcase` goes fullscreen through `setFullscreen()`, lays out inside the safe area, and can import and uninstall mods.
- `tests/MobileTest`: 97 more checks, plus 3 in `ModTest`. All tests also pass compiled to C++.

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
