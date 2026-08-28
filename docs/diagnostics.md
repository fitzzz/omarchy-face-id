# Diagnostic event log

Omarchy Face ID writes privacy-safe diagnostic events to:

```text
~/.local/state/omarchy-face-id/diagnostics.jsonl
```

The location follows `XDG_STATE_HOME` when configured. The active file is owner-readable and owner-writable (`0600`). It rotates at 1 MiB and retains three older files.

## Event envelope

Every line is an independent JSON object:

```json
{
  "schema": "omarchy.face-id.diagnostics.event",
  "schema_version": 1,
  "timestamp_utc": "2026-08-28T21:42:32.341Z",
  "session_id": "7d524315-e94e-44f1-b791-6f7817bfdde1",
  "sequence": 2,
  "level": "info",
  "component": "enrollment.workflow",
  "event": "status_changed",
  "attributes": {
    "step": 1,
    "steps": 5,
    "prompt": "look-straight",
    "done": false
  }
}
```

- `schema` identifies the event family.
- `schema_version` changes only when the envelope becomes incompatible.
- `session_id` is a new random UUID for each application run. It is not derived from the user, machine, or installation.
- `sequence` establishes ordering inside a session even when timestamps collide.
- `component` is a stable dotted subsystem namespace.
- `event` is a stable action or state-transition name.
- `attributes` contains flat typed context that can grow without changing the envelope.

## Privacy boundary

The logger accepts only booleans, numbers, nulls, and short identifier-like strings. A central scrubber rejects sensitive keys and free-form text. The log never records:

- account names, email addresses, hostnames, IP addresses, or home paths;
- camera names, device paths, commands, or raw process output;
- passwords, tokens, raw error messages, or authorization contents;
- camera frames, images, face embeddings, biometric templates, or face names.

Errors use stable categories or D-Bus error identifiers rather than raw messages. Preview events may contain byte counts, state results, and sample counts, but never sample contents.

## Namespace policy

Current top-level components are:

- `app.lifecycle` and `app.environment`
- `dependency.gaze`
- `enrollment.workflow`, `enrollment.gaze_dbus`, `enrollment.camera`, and `enrollment.preview`
- `lock.activation`
- `lock.authentication` for installed lock-screen attempts
- `camera.inventory` for sanitized setup and lock-time camera snapshots

New events extend the narrowest existing component. Add a new top-level component only for a distinct subsystem. Event names describe completed facts such as `claim_finished`, not UI wording.

Camera inventory records logical camera count, USB vendor/product IDs when available, transport class, setup-time capture-format capabilities, Gaze selection mode, and whether an explicit Gaze selection could be matched to an observed camera slot. Lock attempts refresh the count, transport, vendor/product IDs, and selection mapping. The log never stores model names, serial numbers, PipeWire node names, sysfs locations, or `/dev/video*` paths. When Gaze uses `primary`, the daemon chooses the device; diagnostics record that selection honestly as daemon-managed rather than guessing which camera was used.
