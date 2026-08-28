#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
service="$project_root/integration/omarchy-plugin/Service.qml"
pam="$project_root/packaging/pam/omarchy-face-id-lock"
installer="$project_root/scripts/install-lock-integration.sh"

grep -Fq 'config: "omarchy-face-id-lock"' "$service"
grep -Fq 'result === PamResult.Success' "$service"
grep -Fq 'lockService.finishUnlock()' "$service"
grep -Fq 'id: successUnlockTimer' "$service"
grep -Fq 'interval: 650' "$service"
grep -Fq 'onAuthenticatingPasswordChanged' "$service"
grep -Fq 'facePam.abort()' "$service"
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
