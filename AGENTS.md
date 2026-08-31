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
- Every hardware or installation fix requires a regression test and a newly versioned AppImage before it is sent to another tester.
