# Omarchy Face ID

Omarchy Face ID is a standalone setup app and local biometric foundation for Omarchy, powered by [Gaze](https://github.com/GunduLabs/gaze). During setup, the app adds a small Omarchy lock-screen subscriber; the product itself is not an Omarchy plugin. Face ID may add a way in, but it must never remove an existing password path.

The current build includes:

- a Gaze-owned live feed during enrollment;
- an animated face surrounded by radial scan marks;
- a five-angle guided enrollment walkthrough;
- real Gaze enrollment through its system D-Bus service;
- a four-screen Welcome, Prepare, Scan, and Done journey; and
- an update-soft Omarchy lock-screen subscriber;
- a click-through lock-screen face, scan-ring, and checkmark overlay; and
- an Omarchy-targeted AppImage build.

## Platform direction

Enrollment, local matching, liveness checks, and biometric storage form the reusable Face ID foundation. Integrations such as the lock screen remain narrow subscribers with their own authorization policy and failure behavior.

The current release implements only setup, enrollment, and lock-screen authentication. Future password prompts, privilege elevation, passkeys, and other biometric consumers are product direction—not implemented behavior.

## Current safety boundary

The AppImage handles setup and enrollment. The optional lock integration adds a dedicated face-only PAM service and a small Omarchy service plugin. It does not replace the lock screen, edit Omarchy's password service, or alter the shared system authentication stack.

If a later Omarchy update changes the internal lock-service interface, Face ID fails closed: the face attempt stops and the existing password screen continues to work.

## Install Gaze safely on Omarchy

Run this as your normal user:

```bash
./scripts/install-gaze-arch.sh
```

The script downloads Gaze 0.2.12 from its official GitHub release, verifies the pinned SHA-256 digest, installs it with package scriptlets disabled, verifies protected PAM files are unchanged, and enables only `gazed.service`. Afterward, run `gaze doctor` and open the AppImage to enroll.

If Gaze is already installed, the installer leaves it untouched and records no ownership. If Omarchy Face ID installs Gaze, it writes a root-owned receipt so a later uninstall can remove only the dependency it added.

## Run the current AppImage

```bash
chmod +x dist/Omarchy_Face_ID-x86_64.AppImage
APPIMAGE_EXTRACT_AND_RUN=1 ./dist/Omarchy_Face_ID-x86_64.AppImage
```

After saving a face scan, enable the lock-screen subscriber:

```bash
./scripts/install-lock-integration.sh
```

Then lock the computer and look directly at the camera. The lock screen shows a moving face, an orange verification sweep, and a green checkmark before it opens. Password entry remains available throughout.

## Uninstall

Run the full uninstaller from the AppImage as your normal user:

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./dist/Omarchy_Face_ID-x86_64.AppImage --uninstall
```

From a source checkout, `./scripts/uninstall.sh` runs the same command. It removes the saved `default` face enrollment, the dedicated face-only PAM service, and the Omarchy lock-screen subscriber. It removes Gaze only when Omarchy Face ID's root-owned installation receipt proves this project installed it. A Gaze installation that existed before setup is kept. Your password configuration is never removed or replaced. Delete the portable AppImage file afterward if it was not managed by an AppImage installer.

`APPIMAGE_EXTRACT_AND_RUN=1` avoids relying on FUSE. The package intentionally uses the Qt 6 libraries already supplied by Omarchy; bundling a second Linux multimedia stack caused loader conflicts during testing.

## Build from source

Requirements: CMake 3.24 or newer, Ninja, a C++20 compiler, and Qt 6.7 or newer with Core, DBus, Gui, Quick, and Quick Controls 2.

```bash
cmake -S . -B build-native -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build-native
ctest --test-dir build-native --output-on-failure
./build-native/omarchy-face-id
```

Build the AppImage with:

```bash
./scripts/build-appimage.sh
```

The script downloads a pinned, checksum-verified linuxdeploy release to obtain `appimagetool`. The resulting x86-64 file is written under `dist/`.

## Gaze behavior

When `com.gundulabs.Gaze` is present on the system bus, the app claims the current user, starts enrollment, receives Gaze's prompts and preview frames, and releases the claim on completion or cancellation. When the service is missing or stops responding, the app reports that enrollment is unavailable and leaves the operating system untouched.

Gaze is the sole camera owner. The Qt app receives Gaze's preview frames and never opens a competing camera pipeline. Face matching, liveness detection, and biometric storage remain Gaze's responsibility.

## Project status

This is an early development build. The current compatibility integration uses the first-party lock service's existing `finishUnlock()` method and checks for it at runtime. Its visual is a separate, non-interactive Hyprland layer above the lock, so it does not replace the password field or patch Omarchy. A future, supported Omarchy biometric-provider API is still preferred. See [the initial build plan](docs/2026-08-28-initial-build.md).

Project code is GPL-3.0-or-later. The Lucide-derived eye geometry is covered by the notice in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
