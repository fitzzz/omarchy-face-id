#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
service="$project_root/integration/omarchy-plugin/Service.qml"
logger="$project_root/integration/omarchy-plugin/log-event.sh"
pam="$project_root/packaging/pam/omarchy-face-id-lock"
installer="$project_root/scripts/install-lock-integration.sh"
ding="$project_root/assets/ding.mp3"

printf '%s  %s\n' \
    '5df5ca134b7dbec367b339bd50324c8b732c286c3d6e1d3ea2772bf81b1d2347' \
    "$ding" | sha256sum --check --status

grep -Fq 'config: "omarchy-face-id-lock"' "$service"
grep -Fq 'result === PamResult.Success' "$service"
grep -Fq 'lockService.finishUnlock()' "$service"
grep -Fq 'root.playDing()' "$service"
grep -Fq 'command: ["/usr/bin/pw-play", root.dingPath]' "$service"
grep -Fq 'id: successUnlockTimer' "$service"
grep -Fq 'interval: 650' "$service"
grep -Fq 'id: startTimer' "$service"
grep -Fq 'interval: 3000' "$service"
grep -Fq 'scheduleRetry("unauthorized")' "$service"
grep -Fq 'result === PamResult.Failed || result === PamResult.MaxTries' "$service"
grep -Fq 'id: retryTimer' "$service"
grep -Fq 'interval: 2500' "$service"
grep -Fq 'text: indicator.success ? "UNLOCKED"' "$service"
grep -Fq ': indicator.unauthorized ? "LOCKED"' "$service"
grep -Fq 'readonly property color lockedColor: Util.alpha(Color.lock.text, 0.58)' "$service"
grep -Fq 'readonly property color unlockedColor: Color.lock.borderActive' "$service"
grep -Fq 'readonly property color checkingColor: Color.lock.borderActive' "$service"
grep -Fq ': unauthorized ? lockedColor' "$service"
if rg -n '#65d1a7|#f59e0b|#4b5563' "$service"; then
    echo "Lock widget must use Omarchy theme colors instead of fixed status colors." >&2
    exit 1
fi
grep -Fq 'readonly property var verifyingWords' "$service"
grep -Fq '"EXTRAPOLATING"' "$service"
grep -Fq '"SYNTHESIZING"' "$service"
grep -Fq '"DISAMBIGUATING"' "$service"
grep -Fq '"HALLUCINATING"' "$service"
grep -Fq 'id: verifyingWordTimer' "$service"
grep -Fq 'interval: 2000' "$service"
grep -Fq 'id: verifyingWordTransition' "$service"
grep -Fq 'font.pixelSize: Math.max(16, Style.font.caption + 3)' "$service"
if rg -q 'STRUCTURING|DEGRADING|TRUNCATING|VALIDATING' "$service"; then
    echo "Excluded lock-screen status words must not be present." >&2
    exit 1
fi
grep -Fq 'id: keepAwakeTimer' "$service"
grep -Fq 'interval: 3000' "$service"
grep -Fq 'typeof lockService.runWake === "function"' "$service"
grep -Fq 'id: postUnlockWakeTimer' "$service"
grep -Fq 'command: ["omarchy-system-wake"]' "$service"
grep -Fq 'parent.height * 0.5 - height - 74' "$service"
grep -Fq 'onAuthenticatingPasswordChanged' "$service"
grep -Fq 'facePam.abort()' "$service"
grep -Fq 'logDiagnostic("attempt_started"' "$service"
grep -Fq 'logDiagnostic("attempt_finished"' "$service"
grep -Fq 'logDiagnostic("password_fallback_started"' "$service"
grep -Fq 'logDiagnostic("unlock_handoff_requested"' "$service"
grep -Fq "component='lock.authentication'" "$logger"
grep -Fq "component='camera.inventory'" "$logger"
grep -Fq 'camera_selection_observed' "$logger"
grep -Fq 'omarchy.face-id.diagnostics.event' "$logger"
grep -Fq 'WlrLayershell.namespace: "omarchy-face-id-overlay"' "$service"
grep -Fq 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' "$service"
grep -Fq 'mask: Region {}' "$service"
grep -Fq 'above_lock = 1' "$service"

if grep -Fq 'no_screen_share' "$service"; then
    echo "face overlay must not interfere with screenshot capture" >&2
    exit 1
fi

if grep -Fq 'above_lock = 2' "$service"; then
    echo "face overlay must remain non-interactive above the lock" >&2
    exit 1
fi

if rg -n 'omarchy-lock-password|system-auth|pam_unix|pam_faillock' "$pam"; then
    echo "face-only PAM service must not reference a password stack" >&2
    exit 1
fi

non_comment_rules=$(sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "$pam")
[[ $(wc -l <<<"$non_comment_rules") -eq 3 ]]
grep -Eq '^auth[[:space:]]+\[success=done default=ignore\][[:space:]]+pam_gaze\.so$' <<<"$non_comment_rules"
grep -Eq '^auth[[:space:]]+required[[:space:]]+pam_deny\.so$' <<<"$non_comment_rules"
grep -Eq '^account[[:space:]]+required[[:space:]]+pam_permit\.so$' <<<"$non_comment_rules"

if rg -n '/usr/share/omarchy|omarchy-lock-password|system-auth' "$installer"; then
    echo "installer must not edit first-party Omarchy or password PAM files" >&2
    exit 1
fi
