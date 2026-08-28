# Initial build plan: Omarchy Face ID

Date: 2026-08-28
Status: Qt application, Gaze enrollment, and update-soft lock authentication implemented

## Product direction

Build Omarchy Face ID as a local biometric foundation with a Qt 6/QML setup app. Enrollment, matching, liveness, and local storage are the reusable center; the lock screen is the first subscriber. Keep every subscriber independent of Omarchy's first-party files so ordinary updates cannot strand the user behind a broken authentication path.

The current scope stops at enrollment and the lock-screen subscriber. Password prompts, privilege elevation, passkeys, and other biometric consumers are future direction only and must each receive a separate threat model, authorization policy, and recovery design before implementation.

The experience uses a friendly face avatar surrounded by 72 radial scan marks. The face glances, blinks, follows the requested pose, and transitions into a checkmark after a successful scan. The motion is based on the clarity of Apple's Face ID setup language while remaining native to Omarchy's theme. The application does not copy or replace the first-party lock screen.

## What the AppImage can and cannot solve

The AppImage solves distribution of the setup interface, diagnostics, guided enrollment, and explicit subscriber activation. It does not make a sandboxed application into a system authenticator. Each subscriber still requires a trusted Gaze daemon, its PAM module, and a narrow connection to that subscriber's authentication lifecycle.

This creates two layers:

1. **Face ID foundation:** readiness checks, Gaze-owned enrollment, local matching, liveness, biometric storage, status, and recovery guidance.
2. **Lock subscriber:** an isolated PAM service and compatibility plugin that asks the existing Omarchy lock service to finish unlocking only after current face PAM success. The wizard installs this subscriber only after enrollment and explicit system authorization.

## Non-negotiable safety contract

- Password unlock remains visible, focused, and independently usable.
- Face authentication is an optional success path, never a requirement.
- A face mismatch, camera failure, timeout, daemon crash, missing model, update incompatibility, or app removal leaves password authentication unchanged.
- The setup app never edits stock Omarchy files or shared PAM stacks.
- The setup app never runs Gaze's Arch package scriptlet because it automatically changes sudo and polkit authentication. The repository's installer uses pacman's `--noscriptlet` protection and verifies those PAM files remain unchanged.
- Lock-screen integration will use a dedicated face-only PAM service. It will not include `system-auth`, `pam_unix`, `pam_faillock`, sudo, or polkit.
- The project does not clone, replace, or edit Omarchy's lock screen. The compatibility plugin checks for the required lock-service method at runtime and stays inactive if an update removes it.
- Testing of real authentication begins in a disposable account or virtual machine with an out-of-band recovery route, not on the user's only login path.

## Implemented application flow

1. **Welcome:** introduces Face ID and states explicitly that face matching, liveness checks, and biometric data remain local.
2. **Prepare:** helps the user get ready for the scan and presents one human-readable camera state. Package, daemon, and device details stay out of the primary journey.
3. **Scan:** requests enrollment authorization and immediately begins the guided capture. A live preview sits behind the radial face guide. Each straight, up, down, left, and right instruction waits one second and cross-fades in place before capture can naturally progress, then the guide becomes a checkmark.
4. **Done:** offers **Enable Face ID**. This is the only step that requests system authorization for the dedicated lock service and Omarchy plugin. Once enabled, it confirms that Face ID is ready.

The main flow never exposes binary paths, service names, PAM terminology, embeddings, or diagnostic dashboards. When readiness fails, it gives one plain-language recovery action. Technical diagnostics remain available through `gaze doctor` outside the wizard.

Closing or cancelling the application stops the walkthrough and releases its Gaze claim. Opening it never changes PAM or Omarchy configuration; only the final, explicit enablement action does.

## Gaze integration boundary

The client uses Gaze's system D-Bus service:

- service and interface: `com.gundulabs.Gaze`
- object: `/com/gundulabs/Gaze`
- calls: `Claim`, `Release`, `EnrollStart`, `EnrollStop`, and `IsCameraAvailable`
- signals: `EnrollStatus`, `FaceStatus`, and `PreviewFrame`

Gaze owns face matching, local embeddings, liveness checks, infrared support, model files, camera capture, and biometric storage. The Qt app does not reimplement those security-sensitive responsibilities or construct a competing camera pipeline.

## Packaging decision

The package targets Omarchy x86-64 and uses the Qt 6 runtime already installed by Omarchy. Tests showed that fully bundling Qt and a second distribution's multimedia/system libraries could crash in the dynamic loader before application code started. The thin package avoids those conflicting libraries while keeping the compiled QML and application code in one AppImage.

The build script pins and verifies linuxdeploy, extracts its `appimagetool`, builds and tests the application, installs an AppDir, and creates `dist/Omarchy_Face_ID-x86_64.AppImage`.

## Implemented lock integration

- `/etc/pam.d/omarchy-face-id-lock` contains only `pam_gaze`, `pam_deny`, and `pam_permit`; it never includes a password or shared authentication stack.
- The user plugin watches the existing `omarchy.lock` service and begins face PAM after a short secure-surface delay.
- Face authentication waits five seconds after lock so walking away does not immediately unlock the session. During authentication, the subscriber uses the lock service's wake method to keep displays on and prevent its five-second blank timer from racing the unlock.
- Starting password authentication aborts the face attempt immediately.
- Generation checks reject stale results from a previous lock or cancelled attempt.
- Only `PamResult.Success` from the current face attempt may call the existing lock service's `finishUnlock()` method. A 650 ms completion hold makes the verified checkmark visible first.
- Missing PAM, Gaze failure, camera failure, plugin failure, or an incompatible Omarchy update leaves the ordinary password path unchanged.
- A separate, click-through layer-shell surface shows a glancing face while waiting, an orange radial sweep while verifying, and a green checkmark on success.
- Hyprland's non-interactive `above_lock = 1` rule lets that surface render over the session lock without receiving keyboard or pointer input. The overlay does not exclude the display from screenshots and disappears outside the active Face ID states.

Omarchy 4.0 does not expose a supported visual slot *inside* its secure lock surface. The compatibility plugin therefore renders the status as a separate compositor layer and never patches a system QML file. If Hyprland removes or changes `above_lock`, only the visual disappears; face authentication and the first-party password screen keep their independent paths.

## Remaining system work

1. Complete Gaze enrollment and test liveness, camera loss, daemon loss, and spoof resistance on the Logitech C920 and any infrared hardware listed as supported.
2. Exercise password-first cancellation, stale-result rejection, camera loss, and daemon loss on the live lock screen with a recovery console available.
3. Upstream the small, supported Omarchy biometric-provider hook described in [provider-api-v1.md](provider-api-v1.md), replacing the current internal `finishUnlock()` compatibility call.
4. Test the recovery-safe uninstaller on the live environment.
5. Test Omarchy upgrades, suspend/resume, camera reconnect, multi-monitor lock, and simultaneous password/fingerprint attempts.
6. Publish only after the supported hardware table and anti-spoof claims are backed by repeatable results.

## Release gates

A lock-screen-enabled release is blocked until all of these are true:

- Omarchy exposes a supported authentication-provider hook or accepts the proposed equivalent.
- Password-priority cancellation and late-result rejection are verified end to end.
- Installation, upgrade, failure, and removal recovery tests pass.
- Photo and screen-replay resistance claims match measured results on each supported camera tier.

Until those release gates pass, the lock integration remains an explicitly authorized compatibility feature rather than a broadly supported release claim.
