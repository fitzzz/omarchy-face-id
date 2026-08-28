#!/usr/bin/env bash

set -euo pipefail

pam_target=/etc/pam.d/omarchy-lock-face

if omarchy-hyprland-session-locked >/dev/null 2>&1; then
    echo "Unlock the computer before removing face unlock." >&2
    exit 1
fi

omarchy-plugin-disable fitzzz.face-unlock >/dev/null 2>&1 || true

if [[ -e $pam_target ]]; then
    if ! grep -q '^# Face-only service for Omarchy Face Unlock\.' "$pam_target"; then
        echo "$pam_target is not managed by this project; it was left unchanged." >&2
        exit 1
    fi
    sudo unlink "$pam_target"
fi

echo "Face unlock is disabled. Password unlock was not changed."
