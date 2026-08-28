#!/usr/bin/env bash

set -euo pipefail

ownership_dir="${OMARCHY_FACE_ID_OWNERSHIP_DIR:-/var/lib/omarchy-face-id}"
ownership_receipt="$ownership_dir/gaze-installed"
ownership_value='omarchy-face-id:gaze-aur:gaze-bin'
gaze_command="${OMARCHY_FACE_ID_GAZE_COMMAND:-gaze}"
status_file=""
self_delete=0
wizard_mode=0

finish() {
    local exit_code=$?
    trap - EXIT

    if [[ -n $status_file ]]; then
        local status_temp="${status_file}.tmp.$$"
        if ((exit_code == 0)); then
            printf '%s\n' success >"$status_temp"
        else
            printf '%s\n' failure >"$status_temp"
        fi
        mv -f -- "$status_temp" "$status_file"
    fi

    if ((self_delete)); then
        rm -f -- "$0"
    fi
    exit "$exit_code"
}
trap finish EXIT

while (($# > 0)); do
    case "$1" in
        --status-file)
            shift
            status_file=${1:-}
            [[ $status_file == /tmp/omarchy-face-id-install.* ]] || {
                echo "Invalid setup status path." >&2
                exit 2
            }
            ;;
        --self-delete)
            self_delete=1
            ;;
        --wizard)
            wizard_mode=1
            ;;
        --help | -h)
            cat <<'EOF'
Usage: install-gaze-arch.sh [--wizard] [--status-file PATH] [--self-delete]

Install the official Gaze base package through Omarchy's AUR package workflow.
Run this script as the desktop user; package operations request sudo normally.
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
    shift
done

if [[ ${EUID} -eq 0 ]]; then
    echo "Run this as your normal user; setup requests administrator access when needed." >&2
    exit 1
fi

for command_name in omarchy pacman sudo systemctl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Face ID setup needs '$command_name', but it is unavailable." >&2
        exit 1
    fi
done

if ((wizard_mode)); then
    clear 2>/dev/null || true
    printf '\n  Installing Gaze…\n\n'
fi

installed_by_face_id=0
if pacman -Q gaze-bin >/dev/null 2>&1; then
    printf '  Face scanning is already installed.\n'
elif command -v "$gaze_command" >/dev/null 2>&1; then
    printf '  An existing face-scanning installation will be used.\n'
else
    installed_by_face_id=1
    omarchy pkg aur add gaze-bin
fi

sudo systemctl enable --now gazed.service

if ((installed_by_face_id)); then
    receipt_temp=$(mktemp -t omarchy-face-id-receipt.XXXXXX)
    printf '%s\n' "$ownership_value" >"$receipt_temp"
    sudo install -d -o root -g root -m 0755 "$ownership_dir"
    sudo install -o root -g root -m 0644 "$receipt_temp" "$ownership_receipt"
    rm -f -- "$receipt_temp"
fi

if ((wizard_mode)); then
    printf '\n  ✓ Face ID is ready. Returning to setup…\n'
    sleep 1
else
    printf 'Face ID system setup is complete.\n'
fi
