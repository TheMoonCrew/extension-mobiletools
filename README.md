# extension-mobiletools

A small, mobile-focused toolkit for [Lime](https://lime.software) / [OpenFL](https://www.openfl.org) projects.
It exposes common native mobile features through one cross-platform Haxe API, and adds a scripting and modding system on top.

> **Status:** early base (`0.1.0`). The API is small on purpose and will grow.
> The scripting and modding system has automated tests (see [Tests](#tests)). The rest of the Haxe code typechecks for desktop, Android and iOS, and the Android Java code compiles.
> Neither native backend has been run on a real device yet, and the iOS Objective-C++ has not been compiled at all.

## Features

| Feature             | Android | iOS | Other targets  |
| ------------------- | :-----: | :-: | :------------: |
| Runtime permissions |    ✅    |  ✅  | always granted |
| Toast messages      |    ✅    | ✅¹  |     no-op      |
| Vibration           |    ✅    | ✅²  |     no-op      |
| Haptics             |    ✅    |  ✅  |     no-op      |
| Keep screen on      |    ✅    |  ✅  |     no-op      |
| Device info         |    ✅    |  ✅  |    defaults    |
| Storage folders     |    ✅    |  ✅  | working folder |
| Scripting (hscript) |    ✅    |  ✅  |       ✅        |
| Modding             |    ✅    |  ✅  | ✅ (not html5)  |

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

`hscript` is installed as a dependency. It is only compiled into your app if you use `mobiletools.scripting` or `mobiletools.mods`.

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

Two runnable examples live in [`samples/`](samples): `basic` (minimal Lime) and `showcase` (a touch-friendly OpenFL app that exercises every feature, including mods).

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

| Permission         | Android                                                               | iOS                       |
| ------------------ | --------------------------------------------------------------------- | ------------------------- |
| `CAMERA`           | `CAMERA`                                                              | Camera                    |
| `MICROPHONE`       | `RECORD_AUDIO`                                                        | Microphone                |
| `LOCATION`         | `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION`                     | Location, while in use    |
| `NOTIFICATIONS`    | `POST_NOTIFICATIONS` (Android 13+, otherwise always granted)          | Notifications             |
| `IMAGES`           | `READ_MEDIA_IMAGES` (13+), else `READ_EXTERNAL_STORAGE`               | Photo library             |
| `VIDEO`            | `READ_MEDIA_VIDEO` (13+), else `READ_EXTERNAL_STORAGE`                | Photo library (same as `IMAGES`) |
| `AUDIO`            | `READ_MEDIA_AUDIO` (13+), else `READ_EXTERNAL_STORAGE`                | Media / music library     |
| `STORAGE`          | `READ/WRITE_EXTERNAL_STORAGE` up to Android 12L, always granted after | always granted            |
| `EXTERNAL_STORAGE` | Up to Android 10 the storage prompt, Android 11+ "All files access"   | always granted            |
| `BLUETOOTH`        | `BLUETOOTH_CONNECT` + `BLUETOOTH_SCAN` (Android 12+, else always granted) | Bluetooth (iOS 13+)   |
| `CONTACTS`         | `READ_CONTACTS`                                                       | Contacts                  |
| `CALENDAR`         | `READ_CALENDAR` + `WRITE_CALENDAR`                                    | Calendar (full access)    |
| `MOTION`           | `ACTIVITY_RECOGNITION` (Android 10+, else always granted)             | Motion & Fitness          |
| `BIOMETRICS`       | *Availability only*, see below                                        | *Availability only*       |

`EXTERNAL_STORAGE` on Android 11+ does not show a dialog: it opens a system settings screen and the request finishes when the user comes back. Google Play restricts apps that declare `MANAGE_EXTERNAL_STORAGE`, so only use it if you really need to read and write outside your app's folders.

`BIOMETRICS` is different from the rest: neither platform lets an app *ask* for biometrics, so `request()` never shows anything. `check()` tells you whether they can be used:

| Status               | Meaning for `BIOMETRICS`                                   |
| -------------------- | ---------------------------------------------------------- |
| `GRANTED`            | Available and enrolled                                     |
| `DENIED`             | Supported, but nothing is enrolled (or temporarily locked) |
| `DENIED_PERMANENTLY` | iOS only: Face ID was refused for this app                 |
| `RESTRICTED`         | No biometric hardware, or the OS is too old                |

Actually authenticating is not part of this library yet.

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
<config:android permission="android.permission.READ_MEDIA_VIDEO" />      <!-- VIDEO (Android 13+) -->
<config:android permission="android.permission.READ_MEDIA_AUDIO" />      <!-- AUDIO (Android 13+) -->
<config:android permission="android.permission.READ_EXTERNAL_STORAGE" /> <!-- IMAGES, VIDEO, AUDIO, STORAGE (Android 12L and older) -->
<config:android permission="android.permission.WRITE_EXTERNAL_STORAGE" /><!-- STORAGE (Android 12L and older) -->
<config:android permission="android.permission.MANAGE_EXTERNAL_STORAGE" /><!-- EXTERNAL_STORAGE (Android 11+) -->
<config:android permission="android.permission.BLUETOOTH_CONNECT" />     <!-- BLUETOOTH (Android 12+) -->
<config:android permission="android.permission.BLUETOOTH_SCAN" />
<config:android permission="android.permission.READ_CONTACTS" />         <!-- CONTACTS -->
<config:android permission="android.permission.READ_CALENDAR" />        <!-- CALENDAR -->
<config:android permission="android.permission.WRITE_CALENDAR" />
<config:android permission="android.permission.ACTIVITY_RECOGNITION" />  <!-- MOTION (Android 10+) -->
<config:android permission="android.permission.USE_BIOMETRIC" />         <!-- BIOMETRICS -->
```

Without the manifest entry Android denies the request immediately. Runtime permissions need target SDK 23 or higher.

**iOS** - the app crashes if you request a permission without its usage description. Lime merges every extra `*-Info.plist` placed next to your app's `<app file>-Info.plist`, so create e.g. `Permissions-Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSCameraUsageDescription</key>              <string>Why you need the camera</string>
	<key>NSMicrophoneUsageDescription</key>          <string>Why you need the microphone</string>
	<key>NSLocationWhenInUseUsageDescription</key>   <string>Why you need your location</string>
	<key>NSPhotoLibraryUsageDescription</key>        <string>Why you need your photos and videos</string>
	<key>NSAppleMusicUsageDescription</key>          <string>Why you need your music</string>
	<key>NSBluetoothAlwaysUsageDescription</key>     <string>Why you need Bluetooth</string>
	<key>NSContactsUsageDescription</key>            <string>Why you need your contacts</string>
	<key>NSCalendarsUsageDescription</key>           <string>Why you need your calendar</string>
	<key>NSCalendarsFullAccessUsageDescription</key> <string>Why you need your calendar (iOS 17+)</string>
	<key>NSMotionUsageDescription</key>              <string>Why you need motion data</string>
	<key>NSFaceIDUsageDescription</key>              <string>Why you use Face ID</string>
</dict>
</plist>
```

and copy it into the Xcode project folder (`MyApp` = your `<app file="...">`):

```xml
<template path="Permissions-Info.plist" rename="MyApp/Permissions-Info.plist" if="ios" />
```

Notifications, `STORAGE` and `EXTERNAL_STORAGE` need no plist key.

## Storage folders

```haxe
var mods = MobileTools.getDirectory(APP_EXTERNAL) + '/mods';
```

| Directory      | Android                                                      | iOS                      |
| -------------- | ------------------------------------------------------------ | ------------------------ |
| `INTERNAL`     | App private folder, never visible to the user                | Application Support      |
| `APP_EXTERNAL` | `Android/data/<package>/files`, no permission needed         | Documents                |
| `SHARED`       | Root of shared storage (needs `EXTERNAL_STORAGE` to write)   | Documents (no shared storage on iOS) |

On desktop all three are the working directory. Paths have no trailing slash, and are empty when unavailable.

## Scripting

`mobiletools.scripting.Script` runs [hscript](https://github.com/HaxeFoundation/hscript) code (Haxe-like syntax, interpreted at runtime) in a sandbox.

```haxe
import mobiletools.scripting.Script;

var script = Script.fromString('
    var score = 0;
    function addPoints(n) { score += n; mobile.selection(); return score; }
', 'level1.hx');

script.call('addPoints', [10]);   // 10
script.get('score');              // 10
script.has('onUpdate');           // false, so optional hooks are safe to call
```

Errors are thrown as a `String` that names the script and function.

**What scripts can use.** Only what they are given: `Std`, `Math`, `StringTools`, `Json` (`parse`, `stringify`, `prettyStringify`) and `mobile`:

```haxe
mobile.showToast('Hi');                mobile.showLongToast('Hi');
mobile.vibrate(100);                   mobile.selection();
mobile.impact('heavy');                // light, medium, heavy, soft, rigid
mobile.notification('success');        // success, warning, error
mobile.getDeviceInfo();                mobile.isMobile / mobile.isSupported
```

Give a script more by passing `globals` to `Script.fromString`, or `ModManager.expose()` for mods.

**Sandbox.** `Reflect`, `Type`, `Sys` and file access are never exposed, and `new SomeClass()` only works for a short allow list (`StringBuf`, `EReg`, `Date`, `StringMap`, `IntMap`). Plain hscript would let a script create *any* class in your app, so this is replaced. Open one up with `Script.allowClass('haxe.ds.ObjectMap')`, but the class must be part of your app: Haxe removes classes nothing uses, so mark it `@:keep`.

**Things to know:**

- There is no time limit: a script with an endless loop freezes the app.
- Declare a top-level `var` *before* the functions that use it.
- Define `hscriptPos` (`<haxedef name="hscriptPos" />`) if you want line numbers in script errors.
- Reflection is slower and less portable on some targets: scripts call functions with all their arguments, since optional ones are not reliable.

## Modding

`mobiletools.mods.ModManager` finds mods in folders, enables them, runs their scripts and serves their files.

```haxe
import mobiletools.mods.ModManager;

ModManager.init();                              // looks in <APP_EXTERNAL>/mods and restores what was enabled
ModManager.onLog = (source, msg) -> trace('[$source] $msg');
ModManager.onError = (source, msg) -> trace('Mod problem: $source: $msg');

for (mod in ModManager.mods)
    trace('${mod.name} ${mod.enabled}');

ModManager.enable('cool-colors');               // enables its dependencies first
ModManager.disable('cool-colors');
ModManager.move('cool-colors', 0);              // later mods win shared files

var path = ModManager.findFile('images/bg.png'); // from the highest priority enabled mod, or null
var text = ModManager.readText('data/levels.json');

// in your game loop
ModManager.update(elapsed);                     // calls onUpdate(elapsed) in every enabled mod
ModManager.call('onScore', [100]);              // calls your own hook in every enabled mod
```

Which mods are enabled and their order are saved between launches.

### A mod

```
hello-mod/
├── mod.json
├── scripts/
│   └── main.hx
└── images/bg.png        any files you want to replace or add
```

```json
{
    "id": "hello-mod",
    "name": "Hello Mod",
    "version": "1.0.0",
    "author": "Ana",
    "description": "Says hello.",
    "dependencies": ["base-pack"],
    "scripts": ["scripts/main.hx"]
}
```

Only `name` is required. `id` defaults to the folder name, and `scripts` defaults to everything in `scripts/`.

```haxe
// scripts/main.hx
var taps = 0;

function onLoad()   { mod.log('loaded'); mobile.showToast('Hello!'); }
function onUnload() { mod.log('bye'); }
function onUpdate(elapsed) { }
function onTap()    { taps++; mobile.impact('light'); return taps; }
```

Besides `mobile` and anything you expose, each script gets a `mod` object: `mod.id`, `mod.name`, `mod.version`, `mod.log(msg)`, `mod.exists(file)`, `mod.readText(file)`, `mod.readJson(file)` and `mod.list(folder)`. These only reach inside the mod's own folder: absolute paths, `..` and symbolic links pointing outside are refused.

A mod that fails to load (bad script, missing or circular dependency) stays disabled with `mod.error` set, and never stops the others. A script that throws at runtime is reported to `onError` and skipped.

### Where mods live

`ModManager.init()` looks in `<APP_EXTERNAL>/mods`, which needs no permission. To also use a folder users can reach from a file manager or computer, ask for shared storage:

```haxe
ModManager.useSharedStorage('MyGame', function(ok) trace(ok)); // <shared storage>/MyGame/mods
```

This requests `EXTERNAL_STORAGE`, so declare it as described above. On iOS set `UIFileSharingEnabled` in your Info.plist to see the Documents folder in the Files app. You can add any other folder with `ModManager.addRoot(path)`.

Mods do not exist on html5, which has no file system.

### Giving mods something to do

Mods can only touch what you expose:

```haxe
ModManager.expose('game', {
    addScore: function(points:Int) score += points,
    getLevel: function() return currentLevel
});
```

Keep it small, and validate arguments: scripts come from files the user downloaded.

## Tests

```bash
haxe tests/test.hxml
```

Runs the scripting, sandbox and mod system tests (69 checks) on Haxe's interpreter, inside a temporary folder. They also pass compiled to neko and with `hscriptPos` defined. They have not been run compiled to C++, the target used on Android and iOS.

## Project layout

```
src/mobiletools/          Haxe API (MobileTools, Permissions, Haptics, ...)
src/mobiletools/backend/  Platform backends (IBackend, AndroidBackend, IOSBackend, NullBackend)
src/mobiletools/scripting/ hscript sandbox (Script, ScriptInterp, ScriptApi)
src/mobiletools/mods/     Mod discovery and management (ModManager, Mod, ModInfo)
java/com/mobiletools/     Android native code, called through JNI
project/ios/              iOS native code (Objective-C++), compiled by hxcpp
include.xml               Lime build config (Java sources, iOS frameworks)
samples/basic/            Minimal Lime sample
samples/showcase/         Touch UI demo app (OpenFL)
tests/                    Scripting and modding tests
```

## Adding a backend

1. Implement `mobiletools.backend.IBackend`.
2. Select it for your target in `MobileTools.createBackend()`.
3. Add any native sources / permissions to `include.xml`.

## License

MIT - see [LICENSE](LICENSE).
