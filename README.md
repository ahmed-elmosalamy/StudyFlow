# StudyFlow

An offline-first study planner for Android. Organize learning around goals,
subjects, and topics; generate a deterministic study schedule from your weekly
availability; run focus timers; and track progress over time. All data stays on
the device — no accounts, cloud sync, ads, or AI.

## Requirements

- Flutter 3.44.x / Dart 3.12.x
- Android SDK (compileSdk/targetSdk as configured by Flutter)

## Run

Start an emulator or connect a device, then:

```sh
flutter run
```

To install without attaching the debugger:

```sh
flutter install --debug -d emulator-5554
```

## Test

```sh
flutter test
```

## Build

```sh
flutter build apk --release
```

The release build enables R8 code shrinking and resource shrinking
(`android/app/build.gradle.kts` + `android/app/proguard-rules.pro`). It is
currently signed with the debug key so `flutter run --release` works; provide a
real signing config before publishing.

## Known emulator issue: black screen

On some emulator quick-boot snapshots the WindowManager state gets corrupted:
every app window is composited with `mShownAlpha=0.0` (the app is running and
has drawn, but nothing is visible). All apps are affected; the launcher still
works.

Fix:

```sh
adb reboot
```

If the problem survives a normal reboot, cold boot the emulator without loading
a snapshot:

```sh
emulator -avd <name> -no-snapshot-load
```

This is an emulator/quick-boot issue, not an app bug.
