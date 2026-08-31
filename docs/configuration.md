# Configuration

Omarchy Face ID follows the XDG Base Directory convention. Its user settings live at:

```text
$XDG_CONFIG_HOME/omarchy-face-id/config.toml
```

When `XDG_CONFIG_HOME` is unset, that becomes `~/.config/omarchy-face-id/config.toml`. The setup app creates the file once with owner-only permissions. Upgrades never replace an existing file, and the lock-screen subscriber reloads saved changes automatically.

## Lock-screen presence

```toml
schema_version = 1

[lock_screen]
presence_mode = "low_power"
motion_sensitivity = "medium"
start_delay_ms = 3000
rejection_hold_ms = 2500
sleeping_indicator = true
```

`presence_mode` controls what happens after an attempt finds no face or rejects a face:

- `low_power` is the default. A local 160×120 stream runs at 2 FPS while Face ID is in Standby. Movement wakes one authentication attempt. Mouse or keyboard activity is a fallback.
- `on_activity` closes the camera completely while in Standby. Mouse or keyboard activity wakes one authentication attempt.
- `continuous` preserves the earlier behavior and starts another attempt after `rejection_hold_ms`.

`motion_sensitivity` accepts `low`, `medium`, or `high`. Higher sensitivity reacts to smaller visual changes and may wake more often when lighting changes.

`start_delay_ms` controls the pause after the computer locks. Valid values are clamped between 0 and 30000 milliseconds.

`rejection_hold_ms` controls how long the Locked result remains visible. Valid values are clamped between 500 and 10000 milliseconds.

`sleeping_indicator` controls whether the subtle themed Standby widget remains visible. Setting it to `false` hides the widget but does not disable presence detection.

The presence watcher performs only frame-to-frame brightness comparison. It does not identify a person, write camera frames to disk, or access Gaze's face templates. Gaze remains solely responsible for matching and liveness detection after motion wakes an authentication attempt.
