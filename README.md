# extension-mobiletools

A small, mobile-focused toolkit for [Lime](https://lime.software) / [OpenFL](https://www.openfl.org) projects.
It exposes common native mobile features through one cross-platform Haxe API.

> **Status:** early base (`0.1.0`). The API is small on purpose and will grow.
> The Android Java code compiles, but neither backend has been run on a real device yet, and the iOS code has not been compiled at all.

## Features

| Feature             | Android | iOS | Other targets  |
| ------------------- | :-----: | :-: | :------------: |
| Runtime permissions |    ✅    |  ✅  | always granted |
| Toast messages      |    ✅    | ✅¹  |     no-op      |
| Vibration           |    ✅    | ✅²  |     no-op      |
| Haptics             |    ✅    |  ✅  |     no-op      |
| Keep screen on      |    ✅    |  ✅  |     no-op      |
| Device info         |    ✅    |  ✅  |    defaults    |

¹ iOS has no native toast, so it is drawn as an overlay on the key window.
² iOS only has a fixed-length system vibration: the duration is ignored and `cancelVibration()` does nothing.

Unsupported targets never crash: calls are silent no-ops, so you don't need `#if` guards.

## Installation

```bash
haxelib git extension-mobiletools https://github.com/TheMoonCrew/extension-mobiletools
```

Then add it to your `project.xml`:

```xml
<haxelib name="extension-mobiletools" />
```

## Usage

```haxe
import mobiletools.MobileTools;

MobileTools.showToast('Level saved!');              // short toast
MobileTools.showToast('Connection lost', LONG);     // long toast
MobileTools.vibrate(50);                            // 50 ms (Android)
MobileTools.setKeepScreenOn(true);

var info = MobileTools.getDeviceInfo();
trace('${info.manufacturer} ${info.model} - API ${info.apiLevel}');

if (MobileTools.isSupported)
    trace('Native backend active');
```

A runnable example lives in [`samples/basic`](samples/basic).

## Haptics

Semantic feedback for UI interactions. Unlike `vibrate()`, you describe *what happened* and each platform picks the best feel.

```haxe
import mobiletools.Haptics;

Haptics.selection();             // a picker or switch changed
Haptics.impact(MEDIUM);          // LIGHT, MEDIUM, HEAVY, SOFT or RIGID: a button press, a collision
Haptics.notification(SUCCESS);   // SUCCESS, WARNING or ERROR
```

On iOS this uses the Taptic Engine feedback generators. On Android it uses the system's predefined effects (Android 10+) and falls back to short pulses on older versions, so the feel varies with the device's vibration motor. Needs the `VIBRATE` permission, which the library declares for you.

## Permissions

```haxe
import mobiletools.Permissions;

// Ask (shows the system prompt only if the OS still allows it)
Permissions.request(CAMERA, function(status)
{
    if (status.isGranted())
        startCamera();
    else if (status == DENIED_PERMANENTLY)
        Permissions.openSettings(); // the only way to change it now
});

// Check without prompting
var status = Permissions.check(MICROPHONE);

// Several at once, results come back in the same order
Permissions.requestMany([CAMERA, MICROPHONE], function(results) trace(results));
```

Available permissions: `CAMERA`, `MICROPHONE`, `LOCATION` (while in use), `NOTIFICATIONS`, `PHOTOS` (read).

| Status               | Meaning                                                              |
| -------------------- | -------------------------------------------------------------------- |
| `NOT_DETERMINED`     | Never asked, `request()` will prompt                                 |
| `GRANTED`            | Allowed (also returned when the OS has no runtime permission for it) |
| `DENIED`             | Denied, but the system can prompt again (Android)                    |
| `DENIED_PERMANENTLY` | Won't prompt again, use `openSettings()` (every iOS denial)          |
| `RESTRICTED`         | Blocked by the system, e.g. parental controls (iOS)                  |

Callbacks run on the main thread. If no prompt is needed (already granted or permanently denied) the callback runs immediately.

### Declare what you use

The library does **not** declare permissions for you, so your app only ships the ones it needs.

**Android** - add to your `project.xml`:

```xml
<config:android permission="android.permission.CAMERA" />                <!-- CAMERA -->
<config:android permission="android.permission.RECORD_AUDIO" />          <!-- MICROPHONE -->
<config:android permission="android.permission.ACCESS_FINE_LOCATION" />  <!-- LOCATION -->
<config:android permission="android.permission.ACCESS_COARSE_LOCATION" />
<config:android permission="android.permission.POST_NOTIFICATIONS" />    <!-- NOTIFICATIONS (Android 13+) -->
<config:android permission="android.permission.READ_MEDIA_IMAGES" />     <!-- PHOTOS (Android 13+) -->
<config:android permission="android.permission.READ_EXTERNAL_STORAGE" /> <!-- PHOTOS (older) -->
```

Without the manifest entry Android denies the request immediately. Runtime permissions need target SDK 23 or higher.

**iOS** - the app crashes if you request a permission without its usage description. Lime merges every extra `*-Info.plist` placed next to your app's `<app file>-Info.plist`, so create e.g. `Permissions-Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSCameraUsageDescription</key>            <string>Why you need the camera</string>
	<key>NSMicrophoneUsageDescription</key>        <string>Why you need the microphone</string>
	<key>NSLocationWhenInUseUsageDescription</key> <string>Why you need your location</string>
	<key>NSPhotoLibraryUsageDescription</key>      <string>Why you need your photos</string>
</dict>
</plist>
```

and copy it into the Xcode project folder (`MyApp` = your `<app file="...">`):

```xml
<template path="Permissions-Info.plist" rename="MyApp/Permissions-Info.plist" if="ios" />
```

Notifications need no plist key.

## Project layout

```
src/mobiletools/          Haxe API (MobileTools, Permissions, DeviceInfo, ...)
src/mobiletools/backend/  Platform backends (IBackend, AndroidBackend, IOSBackend, NullBackend)
java/com/mobiletools/     Android native code, called through JNI
project/ios/              iOS native code (Objective-C++), compiled by hxcpp
include.xml               Lime build config (Java sources, iOS frameworks)
samples/basic/            Minimal Lime sample
```

## Adding a backend

1. Implement `mobiletools.backend.IBackend`.
2. Select it for your target in `MobileTools.createBackend()`.
3. Add any native sources / permissions to `include.xml`.

## License

MIT - see [LICENSE](LICENSE).
