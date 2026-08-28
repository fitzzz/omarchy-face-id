# Changelog

## 0.2.0 - 2026-08-28

- Replace the experimental Omarchy plugin shell with a Qt 6/QML setup application.
- Add a Gaze-owned live enrollment feed and a five-angle guided walkthrough.
- Add real enrollment support through Gaze's system D-Bus service.
- Add the animated Lucide-derived eye states.
- Add an Omarchy-targeted AppImage build that uses the host Qt runtime to avoid conflicting bundled system libraries.
- Add a checksum-pinned Arch installer that suppresses Gaze's PAM-changing package scriptlet and verifies protected PAM files remain unchanged.
- Redesign setup as a four-screen Welcome, Ready, Scan, and Done journey with plain language and a segmented orbital scan indicator.
- Remove Qt Multimedia from the app so Gaze is always the sole camera owner.
- Add a final **Enable Face Unlock** step so system authorization happens only after enrollment.
- Add a dedicated face-only PAM service and an update-soft Omarchy lock compatibility plugin while leaving password PAM and first-party lock files unchanged.
- Replace the orbital eye with an animated face, 72-mark radial scan, and face-to-checkmark completion transition.
- Use the official Omarchy wordmark geometry in the themed sidebar.

## 0.1.0 - 2026-08-28

- Initialize the Omarchy plugin repository.
- Add an inert service and visual-preview panel.
- Add compatibility diagnostics and a fail-closed preflight prototype.
- Record the password-first safety contract and upstream provider design.
