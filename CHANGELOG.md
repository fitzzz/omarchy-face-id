# Changelog

## Unreleased

- Add a full uninstall command that removes the Face ID enrollment and lock-screen subscriber.
- Track dependency ownership so uninstall removes Gaze only when Omarchy Face ID installed it.
- Clarify that Omarchy Face ID is a standalone app with an Omarchy lock-screen subscriber.
- Wait five seconds before face authentication, keep displays awake while it runs, and restore them after unlock.
- Move the lock-screen Face ID indicator slightly higher.
- Forward terminal input through the AppImage so interactive uninstall confirmation works.

## 0.3.0 - 2026-08-28

- Rename the product, application, package, and repository identity to Omarchy Face ID.
- Reframe the lock screen as the first subscriber to a reusable local biometric foundation.
- Rename the lock subscriber, IPC target, environment variables, and dedicated PAM service.
- Keep password prompts, privilege elevation, passkeys, and other biometric subscribers as documented future direction only.

## 0.2.0 - 2026-08-28

- Replace the experimental Omarchy plugin shell with a Qt 6/QML setup application.
- Add a Gaze-owned live enrollment feed and a five-angle guided walkthrough.
- Add real enrollment support through Gaze's system D-Bus service.
- Add the animated Lucide-derived eye states.
- Add an Omarchy-targeted AppImage build that uses the host Qt runtime to avoid conflicting bundled system libraries.
- Add a checksum-pinned Arch installer that suppresses Gaze's PAM-changing package scriptlet and verifies protected PAM files remain unchanged.
- Redesign setup as a four-screen Welcome, Ready, Scan, and Done journey with plain language and a segmented orbital scan indicator.
- Remove Qt Multimedia from the app so Gaze is always the sole camera owner.
- Add a final **Enable Face ID** step so system authorization happens only after enrollment.
- Add a dedicated face-only PAM service and an update-soft Omarchy lock compatibility plugin while leaving password PAM and first-party lock files unchanged.
- Replace the orbital eye with an animated face, 72-mark radial scan, and face-to-checkmark completion transition.
- Use the official Omarchy wordmark geometry in the themed sidebar.

## 0.1.0 - 2026-08-28

- Initialize the Omarchy plugin repository.
- Add an inert service and visual-preview panel.
- Add compatibility diagnostics and a fail-closed preflight prototype.
- Record the password-first safety contract and upstream provider design.
