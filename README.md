# Omarchy Face Unlock

Omarchy Face Unlock is a Qt 6/QML setup app for checking a webcam and enrolling a face with [Gaze](https://github.com/GunduLabs/gaze). It is designed around one rule: face recognition may add a way in, but it must never take the password path away.

The current build includes:

- a live webcam preview;
- an animated eye that looks left, center, and right and blinks;
- a five-angle guided enrollment walkthrough;
- real Gaze enrollment through its system D-Bus service when Gaze is available;
- a safe preview mode when Gaze is absent; and
- an Omarchy-targeted AppImage build.

## Current safety boundary

The app does **not** edit `/etc/pam.d`, alter Omarchy's lock screen, or enable face unlocking by itself. Gaze's Arch package normally changes sudo and polkit authentication automatically. This project installs the verified package with pacman's `--noscriptlet` protection, then checks that the password, sudo, and polkit PAM files did not change.

The AppImage is the setup and enrollment interface. Actual lock-screen authentication will still require a separately reviewed Gaze daemon/PAM installation and a safe Omarchy integration point. Until those pieces exist, finishing the walkthrough does not change how the computer unlocks.

## Install Gaze safely on Omarchy

Run this as your normal user:

```bash
./scripts/install-gaze-arch.sh
```

The script downloads Gaze 0.2.12 from its official GitHub release, verifies the pinned SHA-256 digest, installs it with package scriptlets disabled, verifies protected PAM files are unchanged, and enables only `gazed.service`. Afterward, run `gaze doctor` and open the AppImage to enroll.

## Run the current AppImage

```bash
chmod +x dist/Omarchy_Face_Unlock-x86_64.AppImage
APPIMAGE_EXTRACT_AND_RUN=1 ./dist/Omarchy_Face_Unlock-x86_64.AppImage
```

`APPIMAGE_EXTRACT_AND_RUN=1` avoids relying on FUSE. The package intentionally uses the Qt 6 libraries already supplied by Omarchy; bundling a second Linux multimedia stack caused loader conflicts during testing.

## Build from source

Requirements: CMake 3.24 or newer, Ninja, a C++20 compiler, and Qt 6.7 or newer with Core, DBus, Gui, Multimedia, Quick, and Quick Controls 2.

```bash
cmake -S . -B build-native -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build-native
ctest --test-dir build-native --output-on-failure
./build-native/omarchy-face-unlock
```

Build the AppImage with:

```bash
./scripts/build-appimage.sh
```

The script downloads a pinned, checksum-verified linuxdeploy release to obtain `appimagetool`. The resulting x86-64 file is written under `dist/`.

## Gaze behavior

When `com.gundulabs.Gaze` is present on the system bus, the app claims the current user, starts enrollment, receives Gaze's prompts and preview frames, and releases the claim on completion or cancellation. When the service is missing or stops responding, the app reports that enrollment is unavailable and leaves the operating system untouched.

The local preview sequence does not perform recognition or liveness detection and does not save biometric data. Those security-sensitive jobs belong to Gaze.

## Project status

This is an early development build, not a complete lock-screen authentication product. The Gaze runtime now has a narrow installation method that leaves unrelated PAM services alone. The remaining blocker is a recovery-tested extension point in Omarchy's first-party lock service. See [the initial build plan](docs/2026-08-28-initial-build.md).

Project code is GPL-3.0-or-later. The Lucide-derived eye geometry is covered by the notice in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
