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
| Haptics + patterns  |    ✅    |  ✅  |     no-op      |
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

Two levels: the platform's own effects for UI feedback, and fully custom patterns.

```haxe
import mobiletools.Haptics;

// Semantic effects: they feel native on each platform
Haptics.selection();             // a picker or switch changed
Haptics.impact(MEDIUM);          // LIGHT, MEDIUM, HEAVY, SOFT or RIGID: a button press, a collision
Haptics.notification(SUCCESS);   // SUCCESS, WARNING or ERROR

// Named patterns: built in, registered by you, or provided by a mod
Haptics.playNamed('heartbeat');  // false if there is no such pattern

// Your own pattern
Haptics.play(new HapticPattern('victory')
    .tap(0, 1, 0.9)              // time (ms), intensity, sharpness
    .tap(120, 0.7, 0.9)
    .hold(300, 250, 0.6)         // time, duration, intensity
    .ramp(600, 400, 0.6, 0));    // time, duration, from, to: a fade out

Haptics.stop();                  // cut a pattern short
```

### Patterns

A `HapticPattern` is a list of events, each with a `time`, a `duration` (0 is a short tap), an `intensity` and a `sharpness` (0 soft, 1 crisp). Besides `tap`, `hold` and `ramp` you can `repeat(count, interval)` what you have so far, and make copies with `scaled(factor)` (intensity) and `stretched(factor)` (speed).

| Platform                          | How a pattern plays                                                                                         |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| iOS with Core Haptics             | Exact timing, intensity and sharpness.                                                                      |
| iOS without Core Haptics          | Approximated with the impact generators, one tap per event.                                                 |
| Android 8+ with amplitude control | A waveform with a strength per moment. Sharpness only shortens taps. Overlapping events keep the strongest. |
| Android without amplitude control | Plain on and off.                                                                                           |

Check what the device supports with `Haptics.capabilities` (`supported`, `amplitudeControl`, `sharpnessControl`).

Patterns are checked as they are built (at most 256 events and 30 seconds, no NaN, intensities clamped to 0-1), because they can come from mods.

### JSON

Patterns load from and save to JSON, which is also how mods ship them:

```json
{
    "name": "hello-wave",
    "events": [
        {"time": 0,   "duration": 120, "intensity": 0.3, "sharpness": 0.2},
        {"time": 140, "duration": 120, "intensity": 0.6},
        {"time": 480, "intensity": 1.0, "sharpness": 1.0}
    ]
}
```

Only `time` is required: `duration` defaults to 0, `intensity` to 1 and `sharpness` to 0.5.

```haxe
var pattern = HapticPattern.fromJson(json);
trace(pattern.toJson(true));
```

### The pattern library

Names resolve through layers, highest priority first: mods, then your own patterns, then the built in ones.

```haxe
Haptics.register('hit', new HapticPattern().tap(0).tap(80, 0.6));   // your own
Haptics.playNamed('hit');
Haptics.unregister('hit');
Haptics.patternNames();    // everything available right now
```

Built in patterns: `double-tap`, `triple-tap`, `knock`, `pulse`, `heartbeat`, `buzz`, `alarm`, `rumble`, `explosion`, `ramp-up`, `ramp-down`. Registering (or a mod providing) a pattern with one of these names replaces it, and removing it brings the original back.

### The user's settings

```haxe
Haptics.enabled = false;     // a master switch for your settings screen: silences everything, mods included
Haptics.intensity = 0.5;     // scales custom patterns (the platform effects have a fixed strength)
```

Scripts cannot change either of these.

Needs the `VIBRATE` permission on Android, which the library declares for you.

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
| `LOCATION_ALWAYS`  | `ACCESS_BACKGROUND_LOCATION` (request `LOCATION` first)               | Location, always          |
| `TRACKING`         | always granted                                                        | App Tracking Transparency (iOS 14+) |
| `PHONE`            | `READ_PHONE_STATE`                                                    | always granted            |
| `NEARBY_WIFI`      | `NEARBY_WIFI_DEVICES` (Android 13+, else always granted)              | always granted            |
| `BODY_SENSORS`     | `BODY_SENSORS`                                                        | always granted (HealthKit is separate) |
| `OVERLAY`          | Draw over other apps (settings screen)                                | always granted            |
| `IGNORE_BATTERY_OPTIMIZATIONS` | Run without battery limits (system dialog)                | always granted            |
| `EXACT_ALARM`      | `SCHEDULE_EXACT_ALARM` (settings screen on Android 12+, else always granted) | always granted     |
| `WRITE_SETTINGS`   | Change system settings (settings screen)                              | always granted            |
| `INSTALL_PACKAGES` | Install other apps (settings screen on Android 8+)                    | always granted            |

**Settings screen permissions.** `EXTERNAL_STORAGE` (Android 11+), `OVERLAY`, `IGNORE_BATTERY_OPTIMIZATIONS`, `EXACT_ALARM`, `WRITE_SETTINGS` and `INSTALL_PACKAGES` are not granted in a dialog: the request opens the matching system screen and finishes when the user comes back. Because that screen can always be opened again, a refusal is `DENIED`, never `DENIED_PERMANENTLY`. Google Play restricts apps that declare `MANAGE_EXTERNAL_STORAGE`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `SCHEDULE_EXACT_ALARM` and `REQUEST_INSTALL_PACKAGES`, so only use them when you really need to.

`LOCATION_ALWAYS` needs `LOCATION` first: from Android 11 the system refuses background location until foreground location is granted, then sends the user to a settings screen. On iOS it upgrades "while using" to "always", which the system offers only once.

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
<config:android permission="android.permission.ACCESS_BACKGROUND_LOCATION" /> <!-- LOCATION_ALWAYS (Android 10+) -->
<config:android permission="android.permission.READ_PHONE_STATE" />      <!-- PHONE -->
<config:android permission="android.permission.NEARBY_WIFI_DEVICES" />   <!-- NEARBY_WIFI (Android 13+) -->
<config:android permission="android.permission.BODY_SENSORS" />          <!-- BODY_SENSORS -->
<config:android permission="android.permission.SYSTEM_ALERT_WINDOW" />   <!-- OVERLAY -->
<config:android permission="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" /> <!-- IGNORE_BATTERY_OPTIMIZATIONS -->
<config:android permission="android.permission.SCHEDULE_EXACT_ALARM" />  <!-- EXACT_ALARM (Android 12+) -->
<config:android permission="android.permission.WRITE_SETTINGS" />        <!-- WRITE_SETTINGS -->
<config:android permission="android.permission.REQUEST_INSTALL_PACKAGES" /> <!-- INSTALL_PACKAGES -->
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
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key> <string>Why you need your location in the background</string>
	<key>NSUserTrackingUsageDescription</key>        <string>Why you track the user</string>
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

**What scripts can use.** Only what they are given: `Std`, `Math`, `StringTools`, `Json` (`parse`, `stringify`, `prettyStringify`), `mobile` and `haptics`:

```haxe
mobile.showToast('Hi');                mobile.showLongToast('Hi');
mobile.vibrate(100);                   mobile.selection();
mobile.impact('heavy');                // light, medium, heavy, soft, rigid
mobile.notification('success');        // success, warning, error
mobile.getDeviceInfo();                mobile.isMobile / mobile.isSupported
```

**Haptics from scripts** (`haptics`) can play named patterns and build new ones. Builder methods return the builder, so calls chain, and trailing arguments are optional:

```haxe
haptics.play('heartbeat');                       // by name, false if unknown
haptics.pattern().tap(0, 1, 0.9).hold(100, 300, 0.5).ramp(400, 300, 0.5, 0).play();
haptics.define('my-hit', haptics.pattern().tap(0).tap(80, 0.6));   // save it for later
haptics.fromJson(text).play();   haptics.fromData({events: [{time: 0}]}).play();
haptics.has('my-hit');   haptics.names();   haptics.stop();
haptics.impact('heavy');   haptics.notification('success');   haptics.selection();
```

`tap(time, [intensity], [sharpness])`, `hold(time, duration, [intensity], [sharpness])`, `ramp(time, duration, from, to, [steps], [sharpness])`, `repeat(count, interval)`, then `play()`, `duration()` or `toJson()`. The limits above apply, and `Haptics.enabled` and `Haptics.intensity` are out of reach.

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
├── haptics/
│   └── hello-wave.json  haptic patterns, see below
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

**Haptic patterns.** Every `haptics/*.json` of an enabled mod becomes available to `Haptics.playNamed()` and to every script, named by the `name` inside the file or else the file name. A mod with the same name as a built in pattern replaces it, the later mod wins between mods, and disabling a mod gives everything back. Patterns a script saves with `haptics.define()` belong to its mod and disappear with it. A broken pattern file is reported to `onError` and skipped, it doesn't stop the mod.

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

Runs two test programs (278 checks) on Haxe's interpreter, inside a temporary folder: `ModTest` (scripting, sandbox, mods) and `HapticTest` (patterns, waveform conversion, the pattern library, the `Haptics` class with a recording backend, the script API and mod provided patterns). They also pass compiled to neko and with `hscriptPos` defined. They have not been run compiled to C++, the target used on Android and iOS.

## Project layout

```
src/mobiletools/          Haxe API (MobileTools, Permissions, Haptics, HapticPattern, ...)
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
2. Select it for your target in `MobileTools.createBackend()`, or install it at runtime with `MobileTools.setBackend()` (handy in tests).
3. Add any native sources / permissions to `include.xml`.

## License

MIT - see [LICENSE](LICENSE).
