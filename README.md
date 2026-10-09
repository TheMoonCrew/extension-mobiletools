# extension-mobiletools

A small, mobile-focused toolkit for [Lime](https://lime.software) / [OpenFL](https://www.openfl.org) projects.
It exposes common native mobile features through one cross-platform Haxe API.

> **Status:** early base (`0.1.0`). The API is small on purpose and will grow.

## Features

| Feature                | Android | iOS | Other targets |
| ---------------------- | :-----: | :-: | :-----------: |
| Toast messages         |    ✅    |  ⏳  |    no-op      |
| Vibration              |    ✅    |  ⏳  |    no-op      |
| Keep screen on         |    ✅    |  ⏳  |    no-op      |
| Device info            |    ✅    |  ⏳  |   defaults    |

✅ implemented · ⏳ planned. Unsupported targets never crash: calls are silent no-ops, so you don't need `#if` guards.

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
MobileTools.vibrate(50);                            // 50 ms
MobileTools.setKeepScreenOn(true);

var info = MobileTools.getDeviceInfo();
trace('${info.manufacturer} ${info.model} - Android API ${info.apiLevel}');

if (MobileTools.isSupported)
    trace('Native backend active');
```

A runnable example lives in [`samples/basic`](samples/basic).

## Project layout

```
src/mobiletools/          Haxe API (MobileTools, DeviceInfo, ToastDuration)
src/mobiletools/backend/  Platform backends (IBackend, AndroidBackend, NullBackend)
java/com/mobiletools/     Android native code, called through JNI
include.xml               Lime build config (Java sources, Android permissions)
samples/basic/            Minimal Lime sample
```

## Adding a backend

1. Implement `mobiletools.backend.IBackend`.
2. Select it for your target in `MobileTools.createBackend()`.
3. Add any native sources / permissions to `include.xml`.

## License

MIT - see [LICENSE](LICENSE).
