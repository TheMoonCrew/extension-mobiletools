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

Two runnable examples live in [`samples/`](samples): `basic` (minimal Lime) and `showcase` (a touch-friendly OpenFL app that exercises every feature).

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

Available permissions:

| Permission         | Android                                                               | iOS                    |
| ------------------ | --------------------------------------------------------------------- | ---------------------- |
| `CAMERA`           | `CAMERA`                                                              | Camera                 |
| `MICROPHONE`       | `RECORD_AUDIO`                                                        | Microphone             |
| `LOCATION`         | `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`                     | Location, while in use |
| `NOTIFICATIONS`    | `POST_NOTIFICATIONS` (Android 13+, otherwise always granted)          | Notifications          |
| `IMAGES`           | `READ_MEDIA_IMAGES` (13+), else `READ_EXTERNAL_STORAGE`               | Photo library          |
| `AUDIO`            | `READ_MEDIA_AUDIO` (13+), else `READ_EXTERNAL_STORAGE`                | Media / music library  |
| `STORAGE`          | `READ/WRITE_EXTERNAL_STORAGE` up to Android 12L, always granted after | always granted         |
| `EXTERNAL_STORAGE` | Up to Android 10 the storage prompt, Android 11+ "All files access"   | always granted         |

`EXTERNAL_STORAGE` on Android 11+ does not show a dialog: it opens a system settings screen and the request finishes when the user comes back. Google Play restricts apps that declare `MANAGE_EXTERNAL_STORAGE`, so only use it if you really need to read and write outside your app's folders.

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
<config:android permission="android.permission.READ_MEDIA_IMAGES" />     <!-- IMAGES (Android 13+) -->
<config:android permission="android.permission.READ_MEDIA_AUDIO" />      <!-- AUDIO (Android 13+) -->
<config:android permission="android.permission.READ_EXTERNAL_STORAGE" /> <!-- IMAGES, AUDIO, STORAGE (Android 12L and older) -->
<config:android permission="android.permission.WRITE_EXTERNAL_STORAGE" /><!-- STORAGE (Android 12L and older) -->
<config:android permission="android.permission.MANAGE_EXTERNAL_STORAGE" /><!-- EXTERNAL_STORAGE (Android 11+) -->
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
	<key>NSAppleMusicUsageDescription</key>        <string>Why you need your music</string>
</dict>
</plist>
```

and copy it into the Xcode project folder (`MyApp` = your `<app file="...">`):

```xml
<template path="Permissions-Info.plist" rename="MyApp/Permissions-Info.plist" if="ios" />
```

Notifications, `STORAGE` and `EXTERNAL_STORAGE` need no plist key.

## Project layout

```
src/mobiletools/          Haxe API (MobileTools, Permissions, DeviceInfo, ...)
src/mobiletools/backend/  Platform backends (IBackend, AndroidBackend, IOSBackend, NullBackend)
java/com/mobiletools/     Android native code, called through JNI
project/ios/              iOS native code (Objective-C++), compiled by hxcpp
include.xml               Lime build config (Java sources, iOS frameworks)
samples/basic/            Minimal Lime sample
samples/showcase/         Touch UI demo app (OpenFL)
```

## Adding a backend

1. Implement `mobiletools.backend.IBackend`.
2. Select it for your target in `MobileTools.createBackend()`.
3. Add any native sources / permissions to `include.xml`.

## License

MIT - see [LICENSE](LICENSE).
