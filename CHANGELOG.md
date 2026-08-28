# Changelog

## Unreleased

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
