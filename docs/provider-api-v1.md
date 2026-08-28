# Historical proposal: Omarchy biometric provider API v1

> This document records the proposed upstream contract for Face ID subscribers. The compatibility lock subscriber works today, but this API is still needed for a supported authentication lifecycle and lock-screen visual slot.

This is a proposal for the smallest upstream Omarchy extension needed by `fitzzz.face-id`. It is not part of the current Omarchy 4.0.0 plugin schema.

## Ownership

The first-party `omarchy.lock` service remains the only owner of `WlSessionLock`, every authentication `PamContext`, the password field, and `finishUnlock()`.

A provider may supply metadata and display-only status. It cannot unlock through plugin IPC.

## Discovery

The enabled plugin manifest requests a `biometric-provider` capability with API version 1. A root-owned descriptor authorizes security-sensitive values:

```json
{
  "schemaVersion": 1,
  "providerId": "fitzzz.face-id",
  "pluginId": "fitzzz.face-id",
  "providerApiVersion": 1,
  "pamService": "omarchy-face-id-lock",
  "preflight": "/usr/libexec/omarchy-face-id-preflight",
  "preflightTimeoutMs": 500,
  "attemptTimeoutMs": 5000,
  "statusCapability": "pam-lifecycle-v1"
}
```

The authoritative descriptor path is `/etc/omarchy/lock-biometric-providers.d/<provider-id>.json`. Omarchy activates a provider only when the enabled manifest and root-owned descriptor agree on provider id, plugin id, and API version.

## Preflight

Before every attempt, Omarchy runs the fixed, root-owned preflight executable with a host-enforced timeout. Exit 0 means an attempt is eligible. Every other result skips the provider. Preflight never authorizes unlock.

## Lifecycle

1. `beginLock()` increments a generation id.
2. A provider starts only after `WlSessionLock.secure` is true.
3. Password submission aborts face authentication without waiting.
4. Only `PamResult.Success` from the current provider context and generation may call idempotent `finishUnlock(generation)`.
5. Late, duplicate, cancelled, and prior-generation results are ignored.
6. Provider failure clears its status and leaves password authentication untouched.

## Version 1 status

Version 1 requires no provider-authored UI and no human-readable message parsing:

- inactive
- checking (`PamContext.active`)
- success (`PamResult.Success`)
- unavailable (non-success completion or preflight failure)

Rich framing and lighting states require a later authenticated observer protocol.
