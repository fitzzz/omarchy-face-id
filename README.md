# Omarchy Face Unlock

An update-safe, local face-authentication integration for Omarchy's first-party lock screen.

This repository is under active development. The current plugin is intentionally inert: it provides compatibility diagnostics and a theme-native indicator preview, but it cannot authenticate or unlock a session. Face authentication stays disabled until Omarchy ships the provider API described in [the initial build design](docs/2026-08-28-initial-build.md).

## Safety contract

- Omarchy's stock password field remains available and independent.
- This plugin never replaces `omarchy.lock` or edits `/etc/pam.d/omarchy-lock-password`.
- Only the first-party lock service may own or release `WlSessionLock`.
- Missing hardware, services, models, configuration, or provider APIs disable face attempts.
- Runtime code never writes inside the git-managed plugin checkout.
- Installation and removal of privileged files will remain explicit and reversible.

## Current development commands

```bash
omarchy plugin validate .
./bin/doctor
./bin/test
```

After installing this repository as an Omarchy plugin, the visual preview can be summoned while the session is unlocked:

```bash
omarchy-shell shell summon fitzzz.face-unlock '{}'
```

Do not install or enable this development build on a machine without an out-of-band recovery path. It does not yet modify PAM, but Omarchy currently has an upstream lock-service reload defect that must be resolved before lock-screen testing.

## Planned backend

The plugin will integrate with [Gaze](https://github.com/GunduLabs/gaze) for on-device recognition, enrollment, PAM authentication, RGB liveness checks, and supported infrared hardware. It will not implement a second face-recognition engine.

## Status

Pre-alpha. Not ready for authentication, PAM changes, or omarchyplugins.com submission.

## License

Project code is licensed under GPL-3.0-or-later. The eye design is derived from Lucide icons under the ISC License; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
