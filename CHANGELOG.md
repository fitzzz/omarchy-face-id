# Changelog

## Unreleased

## 0.7.73 - Test candidate

- Retry Face ID plugin enablement while Omarchy discovers new plugins asynchronously, including after a fallback shell restart. Keep discovery retries bounded and preserve rollback when the plugin never becomes available.

## 0.7.72 - 2026-09-04

- Make an explicit sudo decline interrupt the active PAM conversation before sudo counts a password attempt, so Terminal returns without retry or incorrect-password output.

## 0.7.71 - Test candidate

- Label the delayed sudo approval shortcuts **Hotkey A** and **Hotkey D** beneath their matching buttons.

## 0.7.70 - Test candidate

- Remove the sudo approval deadline so the request remains visible until the user approves, declines, closes it, or sudo itself ends.
- Treat an explicit decline as one cancelled sudo request instead of ten failed password attempts, while technical Face ID failures still fall back to password authentication.
- Remove the unrequested shortcut-delay message and reveal only **Tap A** and **Tap D** after the 1.5-second safety delay.
- Match the setup wizard's 44-pixel button height and shared padding, with a visible themed hover state on the primary Face ID action.

## 0.7.69 - Test candidate

- Give the sudo approval copy and actions equal breathing room beneath the Face ID ring while keeping the avatar fixed in place.
- Center **Tap A** and **Tap D** beneath their matching approval and decline buttons after the shortcut safety delay.

## 0.7.68 - Test candidate

- Keep the sudo Face ID avatar at one fixed position while approval controls, camera guidance, verification, and success states change beneath it.
- Let Omarchy Shell finish its own supported plugin rescan instead of killing it after 1.5 seconds and forcing the updater into a slow restart-recovery path.
- Keep quiet-upgrade output focused on user-facing progress instead of printing a theme debug line on every filesystem-watcher reload.

## 0.7.67 - Test candidate

- Keep one sudo approval window open from conscious approval through Face ID scanning and success, with the existing animated face, a cancellable checking state, and a brief **Approved.** confirmation.
- Run Gaze inside a private root-owned PAM verifier that cannot access the invoking terminal, so successful Face ID authorization no longer prints a second camera prompt or verification message in Terminal.
- Replace the previous sequential consent-and-Gaze PAM rules during upgrades, while every decline, unavailable camera, verifier failure, or closed prompt still preserves password authentication.

## 0.7.66 - Test candidate

- Restore the sudo Face ID overlay when PAM strips Hyprland's instance signature by discovering the compositor that owns the already-validated Wayland display through its user-owned runtime directory.
- Install one reusable live Hyprland rule before the prompt maps, so it appears centered and floating at 560×500 on its first frame instead of briefly opening as a tile.
- Fall back to password without opening a prompt when the Hyprland runtime, lock metadata, compositor process, or control socket cannot be validated.

## 0.7.65 - Test candidate

- Add `--upgrade-quietly` for existing Face ID installations, running the same verified system transaction and Omarchy activation lifecycle without opening the setup wizard.
- Keep quiet upgrades explicit and safe: they preserve the enrolled face, refuse first-run installation, stream progress to the terminal, and retain normal administrator authorization when system files change.

## 0.7.64 - Test candidate

- Keep the standalone sudo consent window at its intended 560×500 overlay size by floating, centering, and raising its exact Hyprland window address without changing user compositor configuration.
- Exercise overlay placement through a fake Hyprland boundary so the regression suite cannot silently accept a tiled consent window again.

## 0.7.63 - Test candidate

- Rebuild the sudo approval window as a self-contained Qt Quick application while preserving Omarchy's semantic theme roles, removing its invalid dependency on Quickshell-only `qs.Ui` and `qs.Commons` modules.
- Exercise the real embedded approval window during automated tests and reject accidental Quickshell imports before packaging.
- Simplify the managed sudo PAM policy to the consent gate and Gaze authentication only, removing compatibility callbacks that made diagnostic logging part of authentication control flow.
- Harden the standalone prompt environment and retain the existing private request channel, explicit approval, local-session checks, and password fallback on every technical failure.

## 0.7.62 - Test candidate

- Restore the sudo Face ID overlay when sudo omits desktop environment variables by discovering and validating the invoking user's Wayland socket inside their private runtime directory.
- Show the updater's current task, including installing Face ID components, registering and enabling Face ID, reloading Omarchy Shell, and waiting for the shell to become ready.

## 0.7.61 - Diagnostic candidate

- Record privacy-safe PAM gate reasons in the system journal when sudo skips the Face ID consent window.
- Record desktop-endpoint, single-flight, and process-channel failures in the existing Face ID diagnostics log instead of silently falling back to a password.

## 0.7.60 - Test candidate

- Repair in-place system-helper upgrades by embedding the ownership marker the installer validates and safely recognizing already-installed `helper 2` binaries from earlier versions.
- Remove root handoff directories after both successful and rolled-back installer transactions.

## 0.7.59 - Test candidate

- Show sudo consent for Omarchy terminals launched through the per-user service manager by validating the requesting user's active local Wayland session instead of requiring the individual sudo process to belong directly to logind; SSH, remote, inactive, and headless requests still use password authentication.

## 0.7.58 - Test candidate

- Never kill an Omarchy Shell restart from the updater. Restart runs independently, survives the AppImage closing, and Face ID readiness is observed afterward without risking the bar, workspace controls, notifications, or lock screen.

## 0.7.57 - Test candidate

- Stream verified installer payloads through a private pipe into root-owned temporary files, because root cannot reopen a desktop user's FUSE-mounted AppImage on standard systems.

## 0.7.56 - Test candidate

- Move sudo approval out of the Omarchy plugin into a short-lived standalone prompt with a private process channel, local-session checks, single-flight protection, explicit approval, and unchanged password fallback.
- Keep the Omarchy plugin responsible only for the lock screen, while reusing its exact themed Face ID avatar and controls in the sudo prompt.
- Install one stable sudo include plus a dedicated Face ID PAM policy through a root-owned, locked transaction that verifies the read-only AppImage payload and rolls back incomplete changes.
- Preserve shared system integration until the final registered user uninstalls, then remove it transactionally without touching pre-existing dependencies.
- Activate lock-screen updates atomically, verify the live service, retry one supported Omarchy Shell restart when needed, and distinguish installed files from a running integration.
- Add privacy-safe sudo consent and face-verification diagnostics without logging commands, identities, paths, or biometric data.
- Rename the update escape action to **Cancel**, remove duplicate retry copy, and add fake-root failure, PAM control-flow, concurrency, runtime reducer, activation lifecycle, and multi-user uninstall coverage.

## 0.7.55 - Test candidate

- Give the sudo approval panel more vertical breathing room and soften its active Omarchy-theme border to 50% opacity.
- Clarify the request with **An app requested sudo access** and **Review the command before approving.**
- Dismiss the approval panel immediately after **Decline** and remember that decision for the complete PAM transaction, preventing sudo retries from reopening Face ID.

## 0.7.54 - Test candidate

- Give returning users a dedicated one-page update experience with no setup steps, camera container, or simulated face scan.
- Introduce the update with the actual AppImage version in **A new version v… is available. Are you ready to install?** and a bottom-right **Continue →** action, without repeating the Face ID eye already present in the sidebar; progress and completion remain **Updating Face ID…** and **Face ID is up to date.**
- Retry the live Face ID shell service while Omarchy finishes registering user plugins instead of reporting a false failure after one early IPC timeout.

## 0.7.53 - Test candidate

- Restore the sudo approval avatar to the lock screen's full size, including its complete animated ring.
- Put **Approve with Face ID** before **Decline** so the buttons and `A` / `D` shortcut legend share the same order.
- Use Omarchy's non-modal on-demand keyboard focus for sudo approval, allowing clicks elsewhere on the desktop while the request remains visible.

## 0.7.52 - Test candidate

- Verify the live Face ID shell service after restart instead of trusting the restart process's exit code, avoiding a false setup error when Omarchy has already loaded the replacement subscriber.

## 0.7.51 - Test candidate

- Normalize the elevation bridge's already-privileged PAM child identity before Qt starts, preventing Qt's setuid safety guard from aborting the sudo consent overlay and dropping directly to the password prompt.
- Reproduce the real/effective UID mismatch in the regression suite without installing a setuid test binary.
- Move the shared Face ID indicator into service-root scope so both the lock-screen and sudo overlays can instantiate it; add a scope regression check for both window variants.
- Give the privileged helper an explicit UTF-8 locale so sudo no longer prints Qt's ANSI locale warning before authentication.
- Replace the oversized circular sudo overlay with a fixed `460 × 340` rounded Omarchy-themed panel that keeps the friendly face visible, reveals shortcuts only when active, and transforms cleanly through decision, verification, success, decline, and password-fallback states.
- Reuse the setup wizard's button component in the installed sudo overlay so primary and secondary actions retain the same readable hover, border, pointer, and motion behavior.
- Restart Omarchy Shell through its supported command after plugin activation and require that reload to succeed before the wizard reports completion, preventing stale overlays from swallowing approval decisions and falling back to a password.

## 0.7.2 - 2026-09-02

- Ask for explicit approval before opening the camera for a sudo request. **Approve Request with Face ID** begins verification; **Decline Request** denies the command.
- Add `A` to approve and `D` to decline, with a 1.5-second safety delay that absorbs stray terminal keystrokes before either shortcut becomes active.
- Add a small purpose-built PAM consent module so an explicit decline denies sudo while unavailable UI, camera, or Face ID infrastructure remains a soft failure that falls back to the unchanged password stack.
- Restyle the desktop approval overlay with Omarchy's active Polkit palette, surface borders, controls, typography, hover states, and pointer cursors.
- Track and uninstall the consent module only when its embedded ownership marker proves it belongs to Omarchy Face ID; foreign system files are never overwritten or removed.
- Add end-to-end Linux-PAM regression coverage for approval, explicit decline, rejected faces, unavailable desktop UI, password fallback, and total denial.

## 0.7.1 - 2026-08-31

- Require an explicit **Yes** in the desktop overlay after a face match, so reviewing a sudo command and proving identity remain separate steps; **No** returns to password authentication without executing the command.
- Add a confirmation-protocol handshake so missing or outdated desktop subscribers fall back to password in under a second instead of making sudo wait.
- Create the elevation bridge's system directory on clean Omarchy installations where `/usr/libexec` does not exist yet.
- Stage the elevation bridge outside the AppImage FUSE mount before sudo installation so root can read it on standard AppImage mounts.
- Scale the enrollment face guide from the camera container's smaller dimension instead of capping it at 350 pixels, keeping it proportional in full-screen and tiled layouts.
- Verify real Linux-PAM control flow in the regression suite, including approval, explicit confirmation denial, face rejection, password fallback, and complete denial.

## 0.7.0 - 2026-08-31

- Make Face ID available automatically for terminal `sudo` approvals while preserving the normal password path on every rejection, camera failure, or unavailable subscriber.
- Add a centered desktop Face ID overlay for terminal approvals using the same animated face component as the lock screen, an 85% opaque black surface, and the active Omarchy theme palette.
- Upgrade existing Face ID installations in place without deleting or recapturing their saved face scan.
- Install a minimal root-to-desktop event bridge so PAM can report privacy-safe checking, locked, and unlocked states without exposing passwords or biometric data.
- Restore a pre-existing Gaze sudo rule on uninstall when Face ID replaced it, while removing the managed rule completely for Gaze installations owned by Face ID.

## 0.6.7 - 2026-08-31

- Keep AppImage-managed Gaze authentication limited to Omarchy Face ID's dedicated lock-screen service by removing the official AUR package's broad sudo and Polkit PAM rules after installation.
- Detect existing AppImage-managed Gaze installs that still have those broad rules and offer a one-click **Finish Setup** repair in the wizard.
- Preserve broad PAM integrations on pre-existing Gaze installations that Omarchy Face ID does not own.
- Replace the repeated enrollment transition message **Wrapping up...** with **Perfect.**

## 0.6.6 - 2026-08-31

- Detect when an Omarchy machine lacks GStreamer JPEG camera support before enrollment instead of letting Gaze fail with **Camera connection lost**.
- Install the official `gst-plugins-good` Arch package through Omarchy as part of the AppImage wizard, including repair of otherwise healthy pre-existing Gaze installations.
- Restart Gaze after adding camera support so the new decoder is available immediately, then continue the wizard automatically.
- Track camera-support package ownership independently and remove it on uninstall only when Omarchy Face ID installed it.
- Stop deliberately terminating bash inside the activation test suite. Existing nonzero-exit, denial, timeout, and bounded-retry scenarios cover the same production recovery path without creating fake system crashes or Omarchy notifications.
- Record the distributable, cross-device AppImage goal and its installation, safety, diagnostics, and hardware-compatibility constraints in `AGENTS.md`.

## 0.6.5 - 2026-08-31

- Add a first-run XDG configuration file at `~/.config/omarchy-face-id/config.toml`, preserve user edits during upgrades, and live-reload lock-screen settings.
- Make low-power presence detection the default: after no face is found or a rejection is shown, Face ID enters a subtle themed Standby state instead of retrying forever.
- Wake one fresh authentication attempt when a 160×120, 2 FPS local motion watcher detects movement, with mouse or keyboard activity as a fallback.
- Keep `on_activity` and legacy `continuous` presence policies available as explicit configuration choices.
- Package and byte-verify the motion watcher with the Omarchy lock subscriber, while keeping all camera frames memory-only.
- Extend privacy-safe diagnostics with presence mode, watcher lifecycle, camera handoff, motion wake, and standby events, using one cross-process lock so concurrent records remain valid JSON Lines.

## 0.6.4 - 2026-08-28

- Add a versioned JSON Lines diagnostic event log with bounded rotation, owner-only permissions, stable subsystem namespaces, per-producer session IDs, severity, sequence numbers, and typed attributes.
- Enforce a central privacy scrubber that excludes account details, paths, device names, raw errors, authorization contents, images, embeddings, and biometric data.
- Trace Gaze setup, D-Bus enrollment, camera and face states, preview negotiation, lock integration activation, and terminal outcomes.
- Trace installed lock-screen authentication attempts, results, retries, password fallback, and successful unlock handoff in the same diagnostic stream.
- Record privacy-safe camera inventory and format capabilities during setup, then refresh camera count, transport, USB vendor/product IDs, and Gaze selection mode during lock usage without serial numbers or device paths.
- Document the event envelope, namespace policy, retention, privacy boundary, and default log location.

## 0.6.3 - 2026-08-28

- Let Gaze establish enrollment capture before attaching the optional local preview, preventing the preview from taking the camera and aborting scans on fresh laptop installations.

## 0.6.2 - 2026-08-28

- Fix final lock-screen activation by following Omarchy's required plugin lifecycle: install the complete subscriber, rescan plugins, then enable it asynchronously.
- Remove the ineffective Gaze reservation workaround; Polkit may correctly authorize with Face ID when Gaze is already wired into system prompts.
- Bound the activation flow so a vanished or hung authorization prompt returns to a retryable state instead of leaving the wizard stuck on **Enabling Face ID…**.
- Update activation tests to model Omarchy's real plugin discovery behavior instead of a blind retry loop.
- Use Omarchy lock/accent theme colors for the lock-screen Face ID widget and derive the rejected **Locked** state from the active lock text color.
- Accept MJPEG PipeWire preview frames on laptops whose cameras do not deliver raw frames to the local scan preview.

## 0.6.1 - 2026-08-28

- Use the active Omarchy theme accent for the Prepare panel border in every dependency and camera state instead of showing missing Gaze as a red error.
- Add breathing room between the Prepare illustration and **Camera Ready** label.
- Remove the enrollment avatar's nose so its animated eyes cannot overlap the center geometry.

## 0.6.0 - 2026-08-28

- Play the bundled CC0 `ding.mp3` after successful enrollment and successful Face ID lock-screen authentication.
- Replace **Perfect. Hold still.** with **Wrapping up...** during the final enrollment save.
- Credit the original MLaudio Freesound asset in the third-party notices.
- Describe the final privileged installation as a system approval prompt because Polkit may authorize with either password or Face ID.
- Label the dependency terminal **Installing Gaze…** instead of implying it is installing the Face ID app.
- Keep the Qt wizard responsive while the Gaze enrollment authorization prompt is open, including when it loses focus or the user cancels it.
- Keep Omarchy subscriber discovery and retry work off the Qt UI thread so the final screen cannot freeze on **Enabling Face ID…**.
- Place the final lock-test instruction on two intentional lines.

## 0.5.4 - 2026-08-28

- Describe final activation as system approval instead of promising a password flow, because a pre-existing Gaze installation may authorize Polkit with the enrolled face.

## 0.5.3 - 2026-08-28

- Render the enrollment ring and scan panel border with the active Omarchy theme accent instead of the warning color.
- Keep the setup wizard in an explicit **Enabling Face ID…** state while Omarchy discovers the new lock-screen subscriber.
- Retry subscriber activation during Omarchy's asynchronous plugin reload instead of presenting a false failure after successful authorization.

## 0.5.2 - 2026-08-28

- Explain Gaze in terms of local liveness detection and infrared camera support instead of exposing unrelated package side effects.
- Rename the dependency step to **Install Gaze from AUR**.
- Remove the repeated password reassurance from the setup interface.
- Show **Start Gaze Service** instead of an installation action when Gaze is already present but stopped.

## 0.5.1 - 2026-08-28

- Remove the ambiguous legacy unversioned AppImage during packaging so testers cannot accidentally receive a stale setup flow.
- Make double-clicking the AppImage the normal launch path and keep extract-and-run as an undocumented troubleshooting fallback.

## 0.5.0 - 2026-08-28

- Add a full uninstall command that removes the Face ID enrollment and lock-screen subscriber.
- Track dependency ownership so uninstall removes Gaze only when Omarchy Face ID installed it.
- Clarify that Omarchy Face ID is a standalone app with an Omarchy lock-screen subscriber.
- Wait three seconds before face authentication, keep displays awake while it runs, and restore them after unlock.
- Move the lock-screen Face ID indicator slightly higher.
- Forward terminal input through the AppImage so interactive uninstall confirmation works.
- Replace the password disclaimer with one clear promise and rename the vague Ready step to Prepare.
- Add the Heroicons long-arrow to forward wizard actions.
- Make Back a quiet action and remove duplicate step counters from page headers.
- Restore live enrollment video with a genuinely shared PipeWire stream, pace pose instructions, and cross-fade them in place.
- Refine scan copy, punctuation, and navigation while keeping Back visually quiet.
- Keep the preview frame fixed between Prepare and Scan and clarify the final lock-screen instruction.
- Show rejected faces as Locked in a wallpaper-neutral slate gray and wait 2.5 seconds before trying again.
- Enlarge lock-screen status labels and replace Verifying with synchronized processing words that cross-fade every two seconds.
- Add Install Gaze Package to the Prepare step using Omarchy's official AUR workflow, then continue setup automatically and preserve ownership-aware uninstall.
- Continue lock-screen activation after a harmless Omarchy rescan timeout and keep plugin terminology out of user-facing errors.
- Introduce a single semantic `VERSION` source, versioned AppImage filenames and metadata, executable version reporting, and release-consistency tests.

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
