#!/usr/bin/env bash

set -euo pipefail

pam_target=/etc/pam.d/omarchy-face-id-lock

if omarchy-hyprland-session-locked >/dev/null 2>&1; then
    echo "Unlock the computer before removing Omarchy Face ID." >&2
    exit 1
fi

omarchy-plugin-disable fitzzz.face-id >/dev/null 2>&1 || true

if [[ -e $pam_target ]]; then
    if ! grep -q '^# Face-only service for Omarchy Face ID\.' "$pam_target"; then
        echo "$pam_target is not managed by this project; it was left unchanged." >&2
        exit 1
    fi
    sudo unlink "$pam_target"
fi

echo "Omarchy Face ID is disabled. Password unlock was not changed."
