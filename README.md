# Omarchy Face ID

Omarchy Face ID is a standalone setup app and local biometric foundation for Omarchy, powered by [Gaze](https://github.com/GunduLabs/gaze). During setup, the app adds a small Omarchy lock-screen subscriber; the product itself is not an Omarchy plugin. Face ID may add a way in, but it must never remove an existing password path.

The current build includes:

- a live enrollment feed using Gaze frames for exclusive cameras and a shared local PipeWire preview when Gaze deliberately omits them;
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

The AppImage handles dependency setup, enrollment, and lock integration. Its own subscriber uses a dedicated face-only PAM service and does not replace the lock screen or edit Omarchy's password service. Installing the official `gaze-bin` dependency runs that package's standard Arch installation hook, which currently adds optional face authentication to sudo and may initialize polkit authentication. Both retain password fallback, and Gaze's official uninstaller reverses those changes when the ownership receipt proves this wizard installed the package.

If a later Omarchy update changes the internal lock-service interface, Face ID fails closed: the face attempt stops and the existing password screen continues to work.

## Install on Omarchy

Send the user only the versioned `Omarchy_Face_ID-0.6.5-x86_64.AppImage`. They double-click it like any other application. If its system component is missing, the Prepare step offers **Install Gaze Package**, opens Omarchy's standard package installer, and continues automatically after the system prompt is approved. The user never needs to know or enter a package command. Internally, the AppImage invokes `omarchy pkg aur add gaze-bin`; it does not download, bundle, fork, or privately distribute Gaze. Normal Omarchy updates therefore keep the package current.

If Gaze was already installed, Face ID uses it without claiming ownership. If the wizard installs it, a root-owned receipt records that fact so Face ID's uninstaller can invoke Gaze's official cleanup and remove the package, its PAM additions, configuration, models, and saved biometric data. The official `gaze-bin` package currently enables Gaze in shared PAM surfaces such as sudo while preserving password fallback; the wizard labels the package installation explicitly rather than hiding that system change.

## Run the current AppImage

```bash
./dist/Omarchy_Face_ID-0.6.5-x86_64.AppImage
```

The wizard enrolls the face and offers to enable the lock-screen subscriber. A short completion sound plays after enrollment and after each successful Face ID unlock. Then lock the computer and look directly at the camera. Face ID appears after three seconds. While scanning, the lock screen cross-fades through a rotating set of short processing words every two seconds. It uses the active Omarchy lock-screen theme for every state. When nobody is present, it settles into a subtle Standby state instead of scanning forever. The default low-power watcher samples a tiny local stream at 2 FPS and wakes one new attempt when it sees movement; frames remain in memory and are never saved. Password entry stays available throughout.

Lock-screen behavior is configurable in `~/.config/omarchy-face-id/config.toml` (or `$XDG_CONFIG_HOME/omarchy-face-id/config.toml`). The app creates this file once, never overwrites user changes, and the installed subscriber reloads edits automatically. See [Configuration](docs/configuration.md).

## Diagnostics

The setup app records privacy-safe structured events in `~/.local/state/omarchy-face-id/diagnostics.jsonl`. The log contains state transitions and sanitized result categories, never usernames, device paths, raw errors, camera images, face embeddings, or biometric templates. Attach that file when reporting an enrollment or activation failure. See [the diagnostic schema](docs/diagnostics.md).

## Uninstall

Run the full uninstaller from the AppImage as your normal user:

```bash
./dist/Omarchy_Face_ID-0.6.5-x86_64.AppImage --uninstall
```

From a source checkout, `./scripts/uninstall.sh` runs the same command. It removes the saved `default` face enrollment, the dedicated face-only PAM service, and the Omarchy lock-screen subscriber. It removes Gaze only when Omarchy Face ID's root-owned installation receipt proves this project installed it. A Gaze installation that existed before setup is kept. Your password configuration is never removed or replaced. Delete the portable AppImage file afterward if it was not managed by an AppImage installer.

The package intentionally uses the Qt 6 libraries already supplied by Omarchy; bundling a second Linux multimedia stack caused loader conflicts during testing.

## Build from source

Requirements: CMake 3.24 or newer, Ninja, pkg-config, GStreamer 1.0 with its app library and PipeWire plugin, a C++20 compiler, and Qt 6.7 or newer with Core, DBus, Gui, Quick, and Quick Controls 2.

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

Every release uses the semantic version in [`VERSION`](VERSION). Update that file and move the completed entries from **Unreleased** into a dated section in [`CHANGELOG.md`](CHANGELOG.md) before distributing a build. The executable, plugin manifest, AppImage metadata, and versioned filename are checked against that release version during packaging.

The script downloads a pinned, checksum-verified linuxdeploy release to obtain `appimagetool`. The resulting x86-64 file is written under `dist/`.

## Gaze behavior

When `com.gundulabs.Gaze` is present on the system bus, the app claims the current user, starts enrollment, receives Gaze's prompts and preview frames, and releases the claim on completion or cancellation. When the service is missing or stops responding, the app reports that enrollment is unavailable and leaves the operating system untouched.

Gaze remains the sole owner of face matching, liveness detection, enrollment, and biometric storage. For exclusive V4L2 or infrared configurations, the app renders Gaze's preview frames. For a PipeWire-only RGB configuration, Gaze 0.2.12 deliberately omits those frames because PipeWire can safely share the camera; the app mirrors Gaze's own GUI behavior by opening a second, display-only PipeWire stream alongside daemon capture. The app never opens the camera through Qt Multimedia or direct V4L2.

## Project status

This is an early development build. The current compatibility integration uses the first-party lock service's existing `finishUnlock()` method and checks for it at runtime. Its visual is a separate, non-interactive Hyprland layer above the lock, so it does not replace the password field or patch Omarchy. A future, supported Omarchy biometric-provider API is still preferred. See [the initial build plan](docs/2026-08-28-initial-build.md).

Project code is GPL-3.0-or-later. The Lucide-derived eye geometry and the CC0 MLaudio completion sound are covered by [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
