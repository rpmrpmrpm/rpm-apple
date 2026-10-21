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

1. The icon font (Font Awesome 5 Pro) is licensed and cannot be published, so it is not in the
   repo. Maintainers run `scripts/copy-icon-fonts.sh` to copy it from the private `rpm-fonts-pro`
   repo. Without it the apps work and some icons are blank.
2. The simulator needs no Apple account. The project names rpm's own team, so Xcode's Signing pane
   may say "No account for team LBW775Z8JG". For the simulator that is expected and does not stop
   the build. To run on your own device, copy `RPM.iOS/Local.xcconfig.example` to
   `RPM.iOS/Local.xcconfig` (and the same in `RPM.tvOS`) and set your own team and bundle id. A
   free Apple ID is enough. Git ignores `Local.xcconfig`.
3. Open `RPM.iOS/rpm.xcodeproj` (or `RPM.tvOS/rpm.xcodeproj`) and run.

Test a module from the command line, for example `RPMKit`:

```
cd RPM.iOS/Modules/RPMKit
swift test
```

Run the tests of each module you changed. To run every module's tests, as CI does:

```
for m in RPM.iOS/Modules/*/; do [ -d "$m/Tests" ] || continue; (cd "$m" && swift test) || echo "FAILED: $m"; done
```

The local library and playback work without an account. The cloud library, catalogue pages and
recognition need an rpm account.

## Licence

[Mozilla Public License 2.0](LICENSE). Third-party files keep their own licence. The name and logo
are reserved: see [TRADEMARKS.md](TRADEMARKS.md).
