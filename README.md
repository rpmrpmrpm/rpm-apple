# rpm for iPhone and Apple TV

The rpm music player for iPhone and Apple TV.

Part of [rpm](https://github.com/rpmrpmrpm/rpm). Ideas and questions go to the
[discussions](https://github.com/rpmrpmrpm/rpm/discussions) there.

## What is here

| Folder | What it is |
| --- | --- |
| `RPM.iOS/rpm.xcodeproj` | The iPhone app. |
| `RPM.iOS/Modules` | Swift packages the apps are built from: `RPMAudio` (playback), `RPMLibrary`, `RPMKit` (network and the rpm server), `RPMUI`, `RPMCast`, `RPMArt` and others. Each has its own tests. |
| `RPM.tvOS/rpm.xcodeproj` | The Apple TV app. |

## Build

You need a Mac with the current Xcode. The iPhone app runs on iOS 17 or later, the Apple TV app on
tvOS 26 or later.

1. The simulator needs no Apple account. To run on your own device, copy
   `RPM.iOS/Local.xcconfig.example` to `RPM.iOS/Local.xcconfig` (and the same in `RPM.tvOS`) and
   set your own team and bundle id. A free Apple ID is enough. Git ignores `Local.xcconfig`.
2. Open `RPM.iOS/rpm.xcodeproj` (or `RPM.tvOS/rpm.xcodeproj`) and run.

Test a module from the command line:

```
cd RPM.iOS/Modules/RPMKit
swift test
```

The local library and playback work without an account. The cloud library, catalogue pages and
recognition need an rpm account.

## Licence

[Mozilla Public License 2.0](LICENSE). Third-party files keep their own licence. The name and logo
are reserved: see [TRADEMARKS.md](TRADEMARKS.md).
