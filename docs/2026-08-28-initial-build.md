# Initial build plan: Omarchy Face Unlock

Date: 2026-08-28
Status: Qt application implemented; system authentication intentionally not enabled

## Product direction

Build a Qt 6/QML AppImage that gives Omarchy users a friendly, guided way to check their webcam and enroll with Gaze. Keep the application independent of Omarchy's lock-screen files so ordinary Omarchy updates do not overwrite it or strand the user at a broken lock screen.

The experience uses a Lucide-derived eye indicator that glances left, centers, glances right, and occasionally blinks. It turns orange while checking and green after successful enrollment. The application follows Omarchy's dark, restrained visual style without copying or replacing the first-party lock screen.

## What the AppImage can and cannot solve

The AppImage solves distribution of the setup interface, camera preview, diagnostics, and guided enrollment. It does not make a sandboxed application into a system authenticator. Face unlock still requires a trusted Gaze daemon, its PAM module, and a narrow connection to Omarchy's lock authentication lifecycle.

This creates two layers:

1. **Portable setup app:** webcam preview, readiness checks, Gaze enrollment, status, and recovery guidance.
2. **System integration:** Gaze runtime, isolated PAM service, and an Omarchy-owned authentication hook. This layer is installed separately only after it passes safety and recovery tests.

## Non-negotiable safety contract

- Password unlock remains visible, focused, and independently usable.
- Face authentication is an optional success path, never a requirement.
- A face mismatch, camera failure, timeout, daemon crash, missing model, update incompatibility, or app removal leaves password authentication unchanged.
- The setup app never edits stock Omarchy files or shared PAM stacks.
- The setup app does not install Gaze's current Arch package because its post-install script automatically changes sudo and polkit authentication.
- Lock-screen integration will use a dedicated face-only PAM service. It will not include `system-auth`, `pam_unix`, `pam_faillock`, sudo, or polkit.
- The project will not clone or replace Omarchy's lock screen. If the required supported hook is absent, face unlock stays disabled.
- Testing of real authentication begins in a disposable account or virtual machine with an out-of-band recovery route, not on the user's only login path.

## Implemented application flow

1. **Welcome:** explains local processing and the password fallback.
2. **Camera:** opens the selected Qt Multimedia video input and shows a live, unsaved preview.
3. **Gaze:** checks `/usr/bin/gaze`, the `com.gundulabs.Gaze` system service, and camera availability reported by Gaze.
4. **Enroll:** guides straight, up, down, left, and right poses. With Gaze installed, prompts, progress, and preview frames come from its D-Bus API. Without Gaze, a clearly labeled demonstration runs and saves nothing.
5. **Finish:** distinguishes real Gaze enrollment from the demonstration and states that lock-screen authentication is still disabled.

Closing or cancelling the application stops the walkthrough and releases its Gaze claim. Opening it never changes PAM or Omarchy configuration.

## Gaze integration boundary

The client uses Gaze's system D-Bus service:

- service and interface: `com.gundulabs.Gaze`
- object: `/com/gundulabs/Gaze`
- calls: `Claim`, `Release`, `EnrollStart`, `EnrollStop`, and `IsCameraAvailable`
- signals: `EnrollStatus`, `FaceStatus`, and `PreviewFrame`

Gaze owns face matching, local embeddings, liveness checks, infrared support, model files, and biometric storage. The Qt app must not reimplement those security-sensitive responsibilities or claim that its demonstration mode performs liveness detection.

## Packaging decision

The package targets Omarchy x86-64 and uses the Qt 6 runtime already installed by Omarchy. Tests showed that fully bundling Qt and a second distribution's multimedia/system libraries could crash in the dynamic loader before application code started. The thin package avoids those conflicting libraries while keeping the compiled QML and application code in one AppImage.

The build script pins and verifies linuxdeploy, extracts its `appimagetool`, builds and tests the application, installs an AppDir, and creates `dist/Omarchy_Face_Unlock-x86_64.AppImage`.

## Remaining system work

1. Obtain or build a Gaze runtime installation path that installs the daemon and PAM module without automatically activating sudo, polkit, login, or a shared PAM stack.
2. Test Gaze enrollment, liveness, camera loss, daemon loss, and spoof resistance on the Logitech C920 and any infrared hardware listed as supported.
3. Add a dedicated, face-only PAM service in a disposable test environment and prove that every failure leaves password authentication working.
4. Integrate with a small, supported Omarchy biometric-provider hook owned by the first-party lock service. The earlier provider proposal remains in [provider-api-v1.md](provider-api-v1.md).
5. Add a recovery-tested installer and uninstaller that are transactional, refuse to run while locked, and never alter stock password files.
6. Test Omarchy upgrades, suspend/resume, camera reconnect, multi-monitor lock, simultaneous password/fingerprint attempts, and stale authentication callbacks.
7. Publish only after the supported hardware table and anti-spoof claims are backed by repeatable results.

## Release gates

A lock-screen-enabled release is blocked until all of these are true:

- Gaze has a narrow no-auto-activation installation route.
- Omarchy exposes a supported authentication-provider hook or accepts the proposed equivalent.
- Password-priority cancellation and late-result rejection are verified end to end.
- Installation, upgrade, failure, and removal recovery tests pass.
- Photo and screen-replay resistance claims match measured results on each supported camera tier.

Until then, this repository ships only the safe setup/enrollment application and makes no changes to the user's unlock path.
