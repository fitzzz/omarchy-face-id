# Project Direction

Omarchy Face ID is a distributable AppImage for real Omarchy users across many machines, camera models, and clean OS installations. The setup wizard must deliver a complete working installation without requiring users or testers to understand Gaze, GStreamer, PAM, Omarchy plugins, camera nodes, or package-manager commands.

## Engineering constraints

- Fix compatibility and dependency problems in the AppImage setup flow. Do not rely on manually repairing an individual test machine.
- Detect missing runtime dependencies and offer the repair inside the wizard, including for users who already have Gaze installed.
- Install packages only through standard Omarchy and Arch package workflows. Do not privately redistribute or fork system dependencies.
- Track ownership of dependencies installed by Omarchy Face ID so uninstall can remove only what this app added and preserve pre-existing software.
- Treat clean Omarchy installations and different RGB, MJPEG, grayscale, and infrared camera configurations as supported product environments.
- Keep password authentication available through every failure. Camera, Gaze, plugin, and theme failures must remain soft failures that cannot lock a user out.
- Keep diagnostics privacy-safe and hardware-useful. Never log images, face templates, account names, device serial numbers, or raw biometric data.
- Build plugin visuals from Omarchy's active semantic theme roles and shared `qs.Ui` components. Build out-of-process visuals from the same semantic theme roles with self-contained Qt components. Do not hard-code status colors, backgrounds, borders, typography, hover states, or pointer behavior.
- Every hardware or installation fix requires a regression test and a newly versioned AppImage before it is sent to another tester.
- Treat builds as test candidates until the user has installed, tested, and explicitly approved them. Do not create or push a Git tag, publish a GitHub release, or call a candidate a release before that approval.
- After a newly versioned test candidate passes its required tests, install it on the maintainer's current machine with `--upgrade-quietly` unless the user says to stop. Check that the Omarchy session is unlocked before any shell reload.
