#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)

if rg -n 'PamContext|WlSessionLock|finishUnlock|Quickshell\.Services\.Pam' \
  "$PROJECT_ROOT/Service.qml" \
  "$PROJECT_ROOT/PreviewPanel.qml" \
  "$PROJECT_ROOT/components"; then
  printf 'runtime plugin code must not own PAM or WlSessionLock\n' >&2
  exit 1
fi

if rg -n 'omarchy-lock-password|pam_unix|pam_faillock|include[[:space:]]+system-auth' \
  "$PROJECT_ROOT/Service.qml" \
  "$PROJECT_ROOT/PreviewPanel.qml" \
  "$PROJECT_ROOT/components" \
  "$PROJECT_ROOT/bin" \
  "$PROJECT_ROOT/lib" \
  "$PROJECT_ROOT/libexec"; then
  printf 'runtime or helper code references the forbidden password PAM path\n' >&2
  exit 1
fi

# This machine does not yet have the required provider API and Gaze profile.
# Preflight must deny an attempt without producing output.
preflight_output=$($PROJECT_ROOT/libexec/omarchy-face-unlock-preflight 2>&1 || true)
[[ -z $preflight_output ]]

# The current source must stay inert until the upstream provider API exists.
report=$($PROJECT_ROOT/bin/doctor --json || true)
jq -e '.ready == false' <<<"$report" >/dev/null
