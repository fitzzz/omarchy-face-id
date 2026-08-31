#!/usr/bin/env bash

set -euo pipefail

ownership_dir="${OMARCHY_FACE_ID_OWNERSHIP_DIR:-/var/lib/omarchy-face-id}"
ownership_receipt="$ownership_dir/gaze-installed"
ownership_value='omarchy-face-id:gaze-aur:gaze-bin'
legacy_ownership_value='omarchy-face-id:gaze:0.2.12-1'
camera_support_receipt="$ownership_dir/camera-support-installed"
camera_support_value='omarchy-face-id:camera-support:gst-plugins-good'
gaze_command="${OMARCHY_FACE_ID_GAZE_COMMAND:-gaze}"
sudo_pam_file="${OMARCHY_FACE_ID_SUDO_PAM_PATH:-/etc/pam.d/sudo}"
polkit_pam_file="${OMARCHY_FACE_ID_POLKIT_PAM_PATH:-/etc/pam.d/polkit-1}"
sudo_pam_marker="${OMARCHY_FACE_ID_GAZE_SUDO_MARKER:-/etc/gaze/pam-arch.configured}"
polkit_pam_marker="${OMARCHY_FACE_ID_GAZE_POLKIT_MARKER:-/etc/gaze/pam-arch.polkit-configured}"
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

Install Gaze and its required camera-format support through Omarchy's package workflows.
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

gaze_missing=1
if pacman -Q gaze-bin >/dev/null 2>&1 \
    || command -v "$gaze_command" >/dev/null 2>&1; then
    gaze_missing=0
fi
camera_support_missing=1
if command -v gst-inspect-1.0 >/dev/null 2>&1 \
    && gst-inspect-1.0 jpegdec >/dev/null 2>&1; then
    camera_support_missing=0
fi

if ((wizard_mode)); then
    clear 2>/dev/null || true
    if ((gaze_missing)); then
        printf '\n  Installing Gaze…\n\n'
    elif ((camera_support_missing)); then
        printf '\n  Installing Camera Support…\n\n'
    else
        printf '\n  Starting Face ID…\n\n'
    fi
fi

camera_support_installed_by_face_id=0
if ((camera_support_missing)); then
    camera_support_installed_by_face_id=1
    omarchy pkg add gst-plugins-good
fi

if ! command -v gst-inspect-1.0 >/dev/null 2>&1 \
    || ! gst-inspect-1.0 jpegdec >/dev/null 2>&1; then
    echo 'Required camera-format support is still unavailable.' >&2
    exit 1
fi

installed_by_face_id=0
managed_by_face_id=0
if ((gaze_missing == 0)) && pacman -Q gaze-bin >/dev/null 2>&1; then
    printf '  Face scanning is already installed.\n'
elif ((gaze_missing == 0)); then
    printf '  An existing face-scanning installation will be used.\n'
else
    installed_by_face_id=1
    omarchy pkg aur add gaze-bin
fi

sudo systemctl enable gazed.service
sudo systemctl restart gazed.service

if ((installed_by_face_id)); then
    receipt_temp=$(mktemp -t omarchy-face-id-receipt.XXXXXX)
    printf '%s\n' "$ownership_value" >"$receipt_temp"
    sudo install -d -o root -g root -m 0755 "$ownership_dir"
    sudo install -o root -g root -m 0644 "$receipt_temp" "$ownership_receipt"
    rm -f -- "$receipt_temp"
fi

if ((installed_by_face_id)) \
    || { [[ -f $ownership_receipt ]] \
        && { [[ $(<"$ownership_receipt") == "$ownership_value" ]] \
            || [[ $(<"$ownership_receipt") == "$legacy_ownership_value" ]]; }; }; then
    managed_by_face_id=1
fi

remove_gaze_auth_rule() {
    local pam_file=$1
    local marker=$2
    [[ -r $pam_file && -r $marker ]] || return 0
    [[ $(<"$marker") == "$pam_file" ]] || return 0

    local pam_temp
    pam_temp=$(mktemp -t omarchy-face-id-pam.XXXXXX)
    awk '!($1 == "auth" && $2 == "sufficient" && $3 == "pam_gaze.so" && NF == 3)' \
        "$pam_file" >"$pam_temp"
    if ! cmp -s "$pam_temp" "$pam_file"; then
        sudo install -o root -g root -m 0644 "$pam_temp" "$pam_file"
    fi
    rm -f -- "$pam_temp"
}

if ((managed_by_face_id)); then
    remove_gaze_auth_rule "$sudo_pam_file" "$sudo_pam_marker"
    remove_gaze_auth_rule "$polkit_pam_file" "$polkit_pam_marker"
    if grep -Eq '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_gaze\.so[[:space:]]*$' \
        "$sudo_pam_file" "$polkit_pam_file" 2>/dev/null; then
        echo 'Face ID could not be limited to the lock screen.' >&2
        exit 1
    fi
fi

if ((camera_support_installed_by_face_id)); then
    receipt_temp=$(mktemp -t omarchy-face-id-camera-support.XXXXXX)
    printf '%s\n' "$camera_support_value" >"$receipt_temp"
    sudo install -d -o root -g root -m 0755 "$ownership_dir"
    sudo install -o root -g root -m 0644 "$receipt_temp" "$camera_support_receipt"
    rm -f -- "$receipt_temp"
fi

if ((wizard_mode)); then
    printf '\n  ✓ Face ID is ready. Returning to setup…\n'
    sleep 1
else
    printf 'Face ID system setup is complete.\n'
fi
