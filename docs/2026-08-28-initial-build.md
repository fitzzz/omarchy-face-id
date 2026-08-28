# Initial build plan: Omarchy Face Unlock

Date: 2026-08-28
Status: Qt application and safe Gaze runtime installation implemented; lock authentication intentionally not enabled

## Product direction

Build a Qt 6/QML AppImage that gives Omarchy users a friendly, guided way to verify Gaze readiness and enroll their face. Keep the application independent of Omarchy's lock-screen files so ordinary Omarchy updates do not overwrite it or strand the user at a broken lock screen.

The experience uses a Lucide-derived eye indicator that glances left, centers, glances right, and occasionally blinks. It turns orange while checking and green after successful enrollment. The application follows Omarchy's dark, restrained visual style without copying or replacing the first-party lock screen.

## What the AppImage can and cannot solve

The AppImage solves distribution of the setup interface, diagnostics, and guided enrollment. It does not make a sandboxed application into a system authenticator. Face unlock still requires a trusted Gaze daemon, its PAM module, and a narrow connection to Omarchy's lock authentication lifecycle.

This creates two layers:

1. **Portable setup app:** readiness checks, Gaze-owned enrollment feed, status, and recovery guidance.
2. **System integration:** Gaze runtime, isolated PAM service, and an Omarchy-owned authentication hook. This layer is installed separately only after it passes safety and recovery tests.

## Non-negotiable safety contract

- Password unlock remains visible, focused, and independently usable.
- Face authentication is an optional success path, never a requirement.
- A face mismatch, camera failure, timeout, daemon crash, missing model, update incompatibility, or app removal leaves password authentication unchanged.
- The setup app never edits stock Omarchy files or shared PAM stacks.
- The setup app never runs Gaze's Arch package scriptlet because it automatically changes sudo and polkit authentication. The repository's installer uses pacman's `--noscriptlet` protection and verifies those PAM files remain unchanged.
- Lock-screen integration will use a dedicated face-only PAM service. It will not include `system-auth`, `pam_unix`, `pam_faillock`, sudo, or polkit.
- The project will not clone or replace Omarchy's lock screen. If the required supported hook is absent, face unlock stays disabled.
- Testing of real authentication begins in a disposable account or virtual machine with an out-of-band recovery route, not on the user's only login path.

## Implemented application flow

1. **Welcome:** promises face unlock with a glance and explains that the face profile stays on this computer.
2. **Ready:** presents one human-readable camera readiness state. Package, daemon, and device details stay out of the primary journey.
3. **Scan:** requests authorization and immediately begins the guided capture. A segmented orbital ring fills as Gaze captures straight, up, down, left, and right views.
4. **Done:** confirms that the face profile was saved locally.

The main flow never exposes binary paths, service names, PAM terminology, embeddings, or diagnostic dashboards. When readiness fails, it gives one plain-language recovery action. Technical diagnostics remain available through `gaze doctor` outside the wizard.

Closing or cancelling the application stops the walkthrough and releases its Gaze claim. Opening it never changes PAM or Omarchy configuration.

## Gaze integration boundary

The client uses Gaze's system D-Bus service:

- service and interface: `com.gundulabs.Gaze`
- object: `/com/gundulabs/Gaze`
- calls: `Claim`, `Release`, `EnrollStart`, `EnrollStop`, and `IsCameraAvailable`
- signals: `EnrollStatus`, `FaceStatus`, and `PreviewFrame`

Gaze owns face matching, local embeddings, liveness checks, infrared support, model files, camera capture, and biometric storage. The Qt app does not reimplement those security-sensitive responsibilities or construct a competing camera pipeline.

## Packaging decision

The package targets Omarchy x86-64 and uses the Qt 6 runtime already installed by Omarchy. Tests showed that fully bundling Qt and a second distribution's multimedia/system libraries could crash in the dynamic loader before application code started. The thin package avoids those conflicting libraries while keeping the compiled QML and application code in one AppImage.

The build script pins and verifies linuxdeploy, extracts its `appimagetool`, builds and tests the application, installs an AppDir, and creates `dist/Omarchy_Face_Unlock-x86_64.AppImage`.

## Remaining system work

1. Complete Gaze enrollment and test liveness, camera loss, daemon loss, and spoof resistance on the Logitech C920 and any infrared hardware listed as supported.
2. Add a dedicated, face-only PAM service in a disposable test environment and prove that every failure leaves password authentication working.
3. Integrate with a small, supported Omarchy biometric-provider hook owned by the first-party lock service. The earlier provider proposal remains in [provider-api-v1.md](provider-api-v1.md).
4. Add a recovery-tested uninstaller that refuses to run while locked and never alters stock password files.
5. Test Omarchy upgrades, suspend/resume, camera reconnect, multi-monitor lock, simultaneous password/fingerprint attempts, and stale authentication callbacks.
6. Publish only after the supported hardware table and anti-spoof claims are backed by repeatable results.

## Release gates

A lock-screen-enabled release is blocked until all of these are true:

- Omarchy exposes a supported authentication-provider hook or accepts the proposed equivalent.
- Password-priority cancellation and late-result rejection are verified end to end.
- Installation, upgrade, failure, and removal recovery tests pass.
- Photo and screen-replay resistance claims match measured results on each supported camera tier.

Until then, this repository ships only the safe setup/enrollment application and makes no changes to the user's unlock path.
