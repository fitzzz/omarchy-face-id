# TODOS

## Authentication

### Require open eyes and direct camera attention

**What:** Require the user's eyes to be open and looking directly at the webcam during enrollment and authentication.

**Why:** The current implementation does not reliably enforce either condition, weakening the intended liveness and attention checks.

**Context:** Add explicit detection thresholds, clear user-facing failure states, and regression tests without weakening the existing look-up, look-down, look-left, and look-right liveness sequence. Validate the behavior across supported RGB and infrared camera paths.

**Effort:** L
**Priority:** P2
**Depends on:** Completion of the lock-screen state-machine and runtime test harness

## Distribution

### Automate verifiable AppImage releases

**What:** Build and publish reproducible x86-64 AppImages through CI with checksums and synchronized download metadata.

**Why:** Public users need a trustworthy artifact whose version, checksum, release entry, and README download link cannot drift apart.

**Context:** Packaging currently runs locally through `scripts/build-appimage.sh`, and the repository has no automated release workflow. Add CI that runs the complete guarded test suite, builds the versioned AppImage, publishes its checksum, and updates or validates release-facing version references. Preserve the rule that no tag, push, or release occurs until the test candidate is approved.

**Effort:** L
**Priority:** P2
**Depends on:** Stabilizing the installer, standalone sudo prompt, and plugin activation architecture
