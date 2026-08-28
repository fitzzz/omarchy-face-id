# Design: Omarchy Face Unlock

Generated on 2026-08-28

Status: APPROVED FOR IMPLEMENTATION PLANNING
Mode: Open source / community

## Product Goal

Add optional face authentication to Omarchy's existing lock screen without replacing or weakening password unlock. The experience should feel native to Omarchy, run entirely on the local machine, resist ordinary photo and screen-replay attacks, and support a stronger infrared path on hardware that Gaze has explicitly detected, configured, and verified. Depth-camera support is future work.

The reference machine uses Omarchy 4.0.0 and a Logitech C920 exposed at `/dev/video0` and `/dev/video1`. A live 640x480 frame was captured successfully during discovery, proving the camera feed is available to host processes.

## Non-Negotiable Safety Contract

Face authentication is an optional success path. It is never a requirement for unlocking.

1. Omarchy's stock password PAM service remains present, visible, focused, and independently functional at all times.
2. The plugin never edits or replaces `/etc/pam.d/omarchy-lock-password`, `system-auth`, or packaged files under `/usr/share/omarchy/`.
3. Face authentication runs in its own PAM service and process boundary. Only a successful result may unlock. Failure, timeout, crash, cancellation, camera loss, missing models, or version mismatch has no effect on password authentication.
4. Face failures do not increment password failure counters or delay password entry.
5. Enabling, disabling, updating, or uninstalling the plugin must not alter the password path.
6. The plugin must never write runtime state, caches, models, or logs inside `~/.config/omarchy/plugins/<plugin-id>/`. Runtime data belongs under standard state/data directories.
7. If the required Omarchy extension point is unavailable or incompatible, the plugin remains absent from the lock screen and reports incompatibility only through unlocked setup and health-check commands. It must not use undocumented lock internals.
8. A public release is blocked until the current Omarchy lock-service reload/stranded-session failure is fixed upstream and verified on the minimum supported Omarchy version.
9. Fault containment is not a security sandbox. Omarchy plugins execute unsandboxed inside `omarchy-shell`; users must trust installed plugin code. The provider contract limits accidental failures but cannot contain a malicious plugin.

## User Experience

The existing password field remains the primary control. A compact eye indicator and one short status line sit beside or immediately below it.

| State | Eye behavior | Color | Text |
| --- | --- | --- | --- |
| Ready/searching | Pupil glances left, center, and right; occasional natural blink | Theme foreground at reduced opacity | `Looking for you...` |
| Face found (rich-status follow-up) | Pupil centers on the user | Orange | `Face found` |
| Verifying | Centered eye with a restrained pulse | Orange | `Checking face...` |
| Success | Centered eye, steady | Green | `Face verified` |
| Unavailable or failed | Animation stops or returns to neutral | Theme-muted, not alarming red | `Face unlock unavailable — use password` |

Password entry never waits for the animation. Typing may continue while face authentication runs; submitting a non-empty password cancels the face attempt immediately and gives password authentication priority.

### Icon Direction

Use Lucide's `Eye` outline as the visual base and its `EyeClosed` form for the blink. Create left, center, and right states by moving the pupil within the same eye outline rather than swapping between unrelated icons. This keeps the shape stable and makes the movement legible at lock-screen size.

Do not use `ScanFace` as the primary status icon. It communicates enrollment or surveillance more strongly than a friendly background unlock attempt. It may be useful in the setup wizard.

The final assets must include Lucide's ISC license notice. Motion must respect any reduced-motion setting; reduced motion uses a static eye plus changing text and color.

Version 1 exposes only coarse states without parsing human-readable messages: neutral before the provider starts, orange/checking while its `PamContext` is active, green on `PamResult.Success`, and muted on a non-successful completion or local compatibility failure. Rich face-found, lighting, and framing states require a supported Gaze observer/status channel and must not be inferred in ways that could mislead the user.

## Authentication Behavior

### Hardware tiers

- **RGB tier:** The architecture accepts usable UVC webcams that pass setup diagnostics, but the public support table lists only devices tested by this project. Version 1 begins with the C920. Use face matching plus passive RGB anti-spoofing and motion evidence. Describe this as convenient face unlock with photo resistance, not hardware-equivalent Face ID.
- **Enhanced tier:** A Gaze-supported infrared camera and, where required, an emitter profile. Setup may detect likely hardware, but the enhanced tier is enabled only after configuration, enrollment, and a successful diagnostic. Depth cameras are not supported in version 1.
- **Reference tier:** Logitech C920 on Omarchy is the first verified RGB configuration, not the only supported device.

### Interaction

Authentication is normally automatic. The user looks toward the camera while the password field remains available. Version 1 uses Gaze's passive liveness and motion evidence. When evidence is inconclusive, the attempt ends and password unlock remains untouched. A randomized blink or small-head-turn challenge is a planned follow-up that requires a supported Gaze protocol; it is not simulated in the Omarchy UI.

The camera activates only while the screen is locked, during explicit enrollment, or during a user-requested diagnostic. It is released immediately after success, cancellation, timeout, or unlock.

Start one face attempt only after `WlSessionLock.secure` becomes true. Allow one retry after a minimum one-second backoff. After two failures, release the camera. Rearm only when the display transitions from blank to awake and at least 15 seconds have passed since the last attempt; pointer movement while the display is already awake does not rearm it. A user may explicitly retry after a five-second cooldown by activating the eye indicator or pressing Enter with an empty password field. No match, poor lighting, or an unknown backend state never trigger unlock.

Gaze currently evaluates a selected detected face and does not give the PAM caller a reliable multi-face count. Version 1 therefore makes no claim that the presence of multiple people will reject authentication. Multi-face rejection requires an upstream Gaze capability before it can become a security promise.

### Required Gaze security profile

The provider checks Gaze configuration before every lock-generation activation, not only during setup. Version 1 requires:

- liveness enabled;
- security level `medium`, `high`, or `maximum`, or a custom profile meeting the project's documented minimums;
- RGB liveness threshold at least `0.8` and no greater than the backend's valid maximum;
- a supported Gaze daemon/PAM version and the expected packaged model identities;
- confirmation mode disabled unless Omarchy implements and verifies the corresponding supported confirmation protocol.

Unknown values, disabled liveness, a lower threshold, unsupported models, or an unreadable live configuration disable the face provider for that attempt. Password authentication is unaffected.

### Privacy

- All inference runs locally. No image, embedding, diagnostic, or telemetry is uploaded.
- Store protected face embeddings rather than ordinary enrollment photographs.
- When a supported TPM is available, setup enables Gaze template encryption and verifies that enrollment can be read through the encrypted path before considering setup complete. Existing plaintext enrollment is migrated only through a Gaze-supported flow; failure leaves the original intact and keeps the provider disabled. Without a supported TPM, setup clearly discloses the filesystem-protected fallback before enrollment. If TPM access later disappears, face authentication fails closed and password unlock remains available. The Omarchy plugin does not implement a second biometric store.
- Document and delegate to Gaze's existing list, refine, remove, and clear commands instead of wrapping them without an Omarchy-specific need.
- Plugin-controlled logs never include camera frames, embeddings, match scores, or biometric values. Setup verifies a production Gaze log level; explicit user-run Gaze verbose diagnostics may show local similarity scores and must be documented separately.

## Recommended Architecture

### Approach A: Omarchy-to-Gaze bridge — selected

Use Gaze as the authentication backend and build a separate Omarchy integration plugin around it.

Gaze already provides the difficult security-sensitive pieces: a local daemon, PAM module, guided multi-angle enrollment, RGB liveness using MiniFASNet-V2, motion checks, infrared support, local face embeddings, diagnostics, and Arch/AUR packages. Reusing it avoids creating a second unreviewed face-recognition stack.

The Omarchy plugin provides:

- Native Quickshell presentation using Omarchy `Color`, `Style`, and `Border` values.
- Eye animation and concise status messages.
- An adapter between Omarchy's lock authentication lifecycle and Gaze's PAM/DBus interfaces.
- Setup, health-check, compatibility-check, and safe-removal commands.
- No machine-learning models or biometric implementation of its own in version 1. A future active challenge belongs in Gaze or a documented Gaze integration API.

This requires a small upstream Omarchy extension point. The preferred contract is a generic optional biometric-provider slot rather than face-specific hard-coding.

### Provider contract version 1

The upstream hook adds a validated `biometric-provider` capability to the Omarchy plugin manifest. Provider metadata contains:

- `apiVersion: 1`
- a display name and stable provider id
- a root-owned PAM service name limited to an `omarchy-lock-*` namespace
- an optional root-owned preflight executable limited to a fixed system path and a host-capped timeout
- optional status capability flags, such as `pam-conversation-v1` or a future `gaze-observer-v1`
- bounded attempt timeout and retry metadata subject to Omarchy-owned maximums

The plugin manifest supplies non-authoritative discovery and presentation metadata. A separate root-owned descriptor at `/etc/omarchy/lock-biometric-providers.d/<provider-id>.json` authorizes the security-sensitive fields: schema version, provider id, plugin id, provider API version, exact `omarchy-lock-*` PAM service, fixed preflight executable, timeout ceilings, and allowed status capability. `omarchy.lock` activates a provider only when the enabled plugin manifest and root descriptor agree exactly on their ids and API version. The root descriptor wins for PAM service and limits; any disagreement disables the provider.

Omarchy validates both records and checks for a compatible API version before loading provider code or starting authentication. Unknown versions, missing PAM services, invalid fields, or unsupported capabilities are ignored. `omarchy.lock`, not provider QML, constructs and owns every provider `PamContext`, renders a generic built-in indicator, and processes its final result.

Before each face attempt, `omarchy.lock` runs the descriptor's root-installed preflight executable with a host-enforced timeout no greater than 500 ms. The executable is outside the writable plugin checkout, owned by root, non-symlinked, and installed at a fixed path such as `/usr/libexec/omarchy-face-unlock-preflight`. It validates the live Gaze security profile, daemon/PAM compatibility, model identities, confirmation mode, and enrollment availability. Exit `0` means the provider is eligible to attempt PAM; any other exit, timeout, crash, missing executable, or malformed behavior skips the attempt. Preflight returns availability only and can never authenticate or authorize unlock.

Version 1 status comes only from `PamContext` lifecycle. A future Gaze observer may supply display-only status through a documented bounded enum, but it can never report authentication success over ordinary plugin IPC.

The lifecycle is:

1. `beginLock()` increments a lock-generation id and resets provider state.
2. Providers start only after the current generation's `WlSessionLock.secure` is true.
3. Password and fingerprint remain independent. Password submission cancels face authentication for that generation without waiting for it.
4. `omarchy.lock` accepts face success only from the current provider `PamContext` and current generation.
5. The first valid authentication success calls one idempotent `finishUnlock(generation)`; all late, duplicate, cancelled, or prior-generation callbacks are ignored.
6. Provider error, timeout, crash, or cancellation clears its indicator and leaves the password field usable.

### Dedicated face PAM service

The lock-only PAM service contains only Gaze authentication and a minimal account result. It must not include `system-auth`, `pam_unix`, `pam_faillock`, sudo, or polkit stacks. The exact installed module path is resolved from the package and verified before the service is enabled. Conceptually:

```text
#%PAM-1.0
auth       [success=done default=ignore]   pam_gaze.so
auth       required                        pam_deny.so
account    required                        pam_permit.so
```

This follows Gaze's own isolated PAM harness pattern: only Gaze success completes authentication; every other result reaches `pam_deny`. Setup parses the resulting service and refuses activation if any unexpected module or include is present. The password PAM service is validated structurally and with an explicit unlocked PAM harness in a visible terminal. The script never reads, captures, or stores the password; PAM owns the interactive prompt. Testing never begins on the real lock screen.

If Omarchy does not accept or ship this hook, the project pauses before public lock-screen integration. It does not ship a fragile substitute.

### Approach B: Self-contained face engine

Implement recognition, embeddings, liveness, storage, camera support, and PAM integration inside this repository.

Rejected because it duplicates current open-source work, creates a much larger security-review burden, and makes hardware compatibility and anti-spoofing our responsibility.

### Approach C: Clone and replace `omarchy.lock`

Clone the first-party lock plugin and add face authentication directly to the copy.

Rejected for public release. It would stop inheriting later Omarchy lock fixes, increase the chance of lockout after updates, and conflict directly with the project's soft-failure requirement. It may only be used in a disposable test environment to prototype the upstream extension contract.

## Installation and Removal

Omarchy's standard plugin installer clones and validates plugin files but does not run install hooks or privileged commands. Setup therefore remains an explicit, reviewable terminal step.

Current Gaze Arch installation is not narrow enough for this design: its post-install flow enables face authentication for sudo and creates a polkit PAM override. The Omarchy plugin must not silently cause those unrelated changes. Public setup therefore requires either an upstream Gaze lock-only/runtime package or an installer mode that installs the daemon and PAM module without activating sudo, polkit, login, or shared authentication stacks. This is a release blocker.

Proposed flow:

1. Install the plugin from its public GitHub URL with `omarchy plugin add`.
2. Run the plugin's setup command while unlocked.
3. Setup installs a supported no-auto-activation Gaze runtime, runs `gaze doctor`, guides enrollment, and creates only the dedicated face PAM service.
4. Setup verifies password authentication independently before enabling face attempts.
5. The plugin starts disabled or inactive when Gaze, enrollment, the PAM service, or the Omarchy provider API is missing.

Setup is transactional and idempotent. Before the first privileged write it records a phase file under the project's state directory. The privileged helper treats that user-owned file only as progress state: every privileged target is a compiled or fixed absolute path, never a path read from the phase file, environment, or plugin-controlled manifest. It rejects symlinks and unexpected ownership on every parent and target, creates files through no-follow/atomic replacement semantics, and never follows a user-selected destination.

Setup creates user state/data directories with mode `0700`, then the root-owned provider descriptor and dedicated PAM service with mode `0644`, validates both, and only then enables the provider. Every completed phase has a matching rollback action. Interrupted setup resumes or rolls back from the phase file.

Removal disables the provider first, waits for an unlocked state, removes only files with exact expected paths and ownership markers, and leaves Gaze enrollment data intact unless the user explicitly requests biometric-data deletion. If a file's contents differ from the recorded installed checksum, removal stops and reports it instead of deleting it. It never removes or rewrites the stock password PAM service.

## Update Compatibility

- Declare and test a minimum and maximum-known Omarchy API version.
- Probe the numeric biometric-provider API and capability flags rather than relying only on package versions. Detect incompatible Omarchy or Gaze versions before provider activation.
- Store no mutable runtime data inside the git-managed plugin checkout.
- Refuse the plugin's own setup/update helper while the session reports locked or lock-requested.
- Document that generic `omarchy plugin update` must be run while unlocked until Omarchy's lock-service reload issue is fixed upstream.
- Test the plugin against current Omarchy before each release and after changes to `omarchy.lock`, the plugin manifest schema, PAM handling, or Quickshell.
- Keep the upstream hook small and generic so later Omarchy lock-screen improvements remain first-party code automatically inherited by users.

## Failure and Security Test Matrix

A release is not ready until these cases leave password unlock working:

- Camera missing, covered, busy, permission-denied, disconnected mid-scan, or returning malformed frames.
- Gaze absent, stopped, crashed, hung, outdated, or returning an unknown status.
- Model missing or corrupted; liveness disabled or weakened; no face enrolled; face mismatch; poor lighting; and multiple people present without making an unsupported rejection claim.
- Printed photo, phone/tablet photo, replayed video, and still-image presentation attempts.
- Password typed or submitted during every face state, including face success arriving at the same moment.
- Fingerprint and face attempts running together.
- Repeated face failures without changes to password `pam_faillock` state.
- Suspend/resume, monitor hotplug, multi-monitor lock surfaces, and camera reconnect.
- Plugin disabled, removed, updated, or made syntactically invalid while unlocked.
- Omarchy updated across each supported version boundary.
- Face daemon killed and plugin process reloaded while the session is locked.
- Face success racing with password submission; late success after cancellation; simultaneous fingerprint/face success; and callbacks from a prior lock generation.
- Reduced-motion and multiple Omarchy themes, including low-contrast palettes.
- Uninstall interrupted at each step.

End-to-end lock tests require a disposable user account or virtual machine plus an out-of-band recovery route. Testing must never begin on the user's only active unlock path.

## Distribution Plan

The repository will be public on GitHub and distributed as a normal Omarchy plugin. Before submission it needs:

- A valid root `manifest.json` and successful `omarchy plugin validate` result.
- README with security tier language, supported hardware, setup, recovery, and removal.
- GPL-3.0-or-later license for project code, plus Lucide attribution and ISC license notice for the icon-derived assets.
- Preview image or short animation showing the indicator states.
- Tagged releases, changelog, and compatibility table.
- CI for manifest validation, QML checks, helper tests, failure-injection tests, and packaging checks.
- A public security policy and private vulnerability-reporting route.

After the first tested release, submit the repository through omarchyplugins.com's plugin issue form. The marketplace validates the listing and manifest, not the plugin's security, so this repository's evidence and warnings remain essential.

## Success Criteria

1. A supported user can install, enroll, lock, and unlock with their face while the password field stays immediately usable.
2. The documented RGB threat tier is backed by repeatable C920 tests against printed photos and phone-screen photo/video replays, with measured false accepts and false rejects. Claims are limited to the evidence.
3. Every injected component failure falls back to password without restarting the shell or changing PAM password behavior.
4. Disabling or removing the plugin restores ordinary Omarchy behavior without editing first-party files.
5. A supported Omarchy update does not require copying or merging the built-in lock plugin.
6. The eye indicator's state and text agree with the backend, remain readable across themes, and do not falsely claim success.

## Release Blockers

- A supported upstream Omarchy biometric-provider extension point.
- Resolution and verification of the active lock-service plugin reload/stranded-session defect.
- A Gaze Arch runtime/install mode that does not automatically modify sudo, polkit, login, or shared PAM stacks.
- Verified `PamContext` lifecycle-to-UI mapping, password-priority cancellation, retry cooldown, and stale-callback behavior; rich face-found/framing status requires a supported observer channel and is not a v1 blocker.
- Compatibility handling for Gaze `require_confirmation_lock_screen`; unsupported confirmation modes disable the provider with unlocked setup guidance.
- Recovery-tested setup and uninstall scripts.
- Documented RGB and infrared security claims backed by repeatable spoof tests on actual supported hardware.

## Initial Build Order

1. Resolve the Gaze lock-only package/install mode and verify its PAM side effects are limited to this project.
2. Prototype an end-to-end disposable biometric provider: PAM success, password-priority cancellation, stale-callback rejection, and coarse status transport.
3. Specify and submit the smallest generic Omarchy biometric-provider hook based on the verified spike.
4. Write a compatibility probe for Omarchy, Gaze, PAM service availability, camera access, enrollment, and confirmation mode.
5. Integrate Gaze in the dedicated face PAM flow with password concurrency preserved.
6. Build the theme-native eye indicator against the proven status mapping.
7. Add transactional enrollment/setup and safe removal.
8. Run the failure matrix, upgrade tests, spoof tests, visual checks, and recovery drills.
9. Publish a tagged GitHub release and submit it to omarchyplugins.com.

## Research Basis

- Omarchy plugin and shell documentation: https://github.com/basecamp/omarchy/blob/quattro/docs/omarchy-shell.md
- Omarchy plugin publishing: https://omarchyplugins.com/publish.html
- Omarchy lock reload defect: https://github.com/basecamp/omarchy/issues/7106
- Gaze Linux face authentication: https://github.com/GunduLabs/gaze
- Gaze configuration and liveness behavior: https://gaze.gundulabs.com/guide/configuration
- Lucide Eye: https://lucide.dev/icons/eye
- Lucide Eye Closed: https://lucide.dev/icons/eye-closed
- Lucide license: https://lucide.dev/license

## Decisions Already Made

- Community/open-source project.
- Broad webcam architecture with an evidence-based tested-device list and setup-verified infrared support.
- Mostly automatic unlock; an active challenge when uncertain remains the desired follow-up after Gaze exposes a supported protocol.
- Animated eye plus short status text; no live camera preview on the lock screen.
- Guided multi-angle enrollment.
- Fully local processing and storage.
- Honest distinction between RGB convenience and stronger supported-infrared protection; depth remains future work.
- Standalone marketplace plugin plus the smallest necessary upstream Omarchy hook; avoid a full upstream-only implementation.

## Open Items That Do Not Block Planning

- Final public plugin id and author namespace, based on the GitHub owner.
- Final product name; `Omarchy Face Unlock` is the working name.
- Exact orange and green tokens after contrast testing against Omarchy themes.
- Whether rich status and the future active challenge land in Gaze or in a documented Gaze integration API.
