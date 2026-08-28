#!/usr/bin/env bash

set -euo pipefail

plugin_id=fitzzz.face-id
plugin_target="${OMARCHY_FACE_ID_PLUGIN_TARGET:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id}"
pam_target="${OMARCHY_FACE_ID_PAM_PATH:-/etc/pam.d/omarchy-face-id-lock}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-face-id"
face_receipt="$state_dir/enrolled-face"
ownership_dir="${OMARCHY_FACE_ID_OWNERSHIP_DIR:-/var/lib/omarchy-face-id}"
gaze_receipt="$ownership_dir/gaze-installed"
expected_gaze_receipt='omarchy-face-id:gaze:0.2.12-1'
expected_gaze_aur_receipt='omarchy-face-id:gaze-aur:gaze-bin'
assume_yes=0

usage() {
    cat <<'EOF'
Usage: Omarchy_Face_ID-x86_64.AppImage --uninstall [--yes]

From a source checkout: ./scripts/uninstall.sh [--yes]

Remove Omarchy Face ID, its saved face scan, and its lock-screen integration.
Gaze is removed only when Omarchy Face ID's installation receipt proves that
this project installed it.
EOF
}

while (($# > 0)); do
    case "$1" in
        --yes | -y)
            assume_yes=1
            ;;
        --help | -h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ ${EUID} -eq 0 ]]; then
    echo "Run this as your normal user; it requests sudo only for system files." >&2
    exit 1
fi

if [[ ${OMARCHY_FACE_ID_SKIP_LOCK_CHECK:-0} != 1 ]] \
    && command -v omarchy-hyprland-session-locked >/dev/null 2>&1 \
    && omarchy-hyprland-session-locked >/dev/null 2>&1; then
    echo "Unlock the computer before uninstalling Omarchy Face ID." >&2
    exit 1
fi

gaze_ownership=none
if [[ -f $gaze_receipt ]]; then
    case $(<"$gaze_receipt") in
        "$expected_gaze_receipt") gaze_ownership=legacy ;;
        "$expected_gaze_aur_receipt") gaze_ownership=aur ;;
    esac
fi
gaze_owned=0
[[ $gaze_ownership == none ]] || gaze_owned=1

face_name=""
if [[ -f $face_receipt ]]; then
    face_name=$(<"$face_receipt")
elif [[ -f $plugin_target/manifest.json ]] \
    && grep -Fq '"id": "fitzzz.face-id"' "$plugin_target/manifest.json"; then
    # Releases before installation receipts always enrolled this one name.
    face_name=default
fi
if [[ -n $face_name ]] && [[ ! $face_name =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "The enrollment receipt is invalid; no face data was changed." >&2
    exit 1
fi

if [[ -e $pam_target ]] \
    && ! grep -q '^# Face-only service for Omarchy Face ID\.' "$pam_target"; then
    echo "$pam_target is not managed by Omarchy Face ID; it was left unchanged." >&2
    exit 1
fi

if ((assume_yes == 0)); then
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "Run interactively or pass --yes." >&2
        exit 1
    fi
    echo "Face ID and its saved face scan will be removed."
    echo "Your password will not change."
    if ((gaze_owned)); then
        echo "The Gaze package will also be removed because Face ID installed it."
    else
        echo "Your existing Gaze installation will remain installed."
    fi
    read -r -p "Continue? [y/N] " answer
    [[ $answer == y || $answer == Y ]] || exit 0
fi

account_name=$(id -un)
if [[ -n $face_name ]] && command -v gaze >/dev/null 2>&1; then
    if gaze list-faces --user "$account_name" 2>/dev/null \
        | grep -Fq "• $face_name "; then
        gaze remove-face "$face_name" --user "$account_name"
    fi
fi

if [[ -e $plugin_target || -L $plugin_target ]]; then
    if [[ ! -f $plugin_target/manifest.json ]] \
        || ! grep -Fq '"id": "fitzzz.face-id"' "$plugin_target/manifest.json"; then
        echo "$plugin_target is not a recognized Omarchy Face ID subscriber; it was left unchanged." >&2
        exit 1
    fi
    omarchy plugin remove "$plugin_id" --yes
fi

if [[ -e $pam_target ]]; then
    sudo unlink "$pam_target"
fi

if ((gaze_owned)); then
    if [[ $gaze_ownership == aur ]] && command -v gaze >/dev/null 2>&1; then
        gaze uninstall --yes
    elif [[ $gaze_ownership == aur ]] && pacman -Q gaze-bin >/dev/null 2>&1; then
        sudo systemctl disable --now gazed.service >/dev/null 2>&1 || true
        omarchy pkg drop gaze-bin
    elif pacman -Q gaze >/dev/null 2>&1; then
        sudo systemctl disable --now gazed.service >/dev/null 2>&1 || true
        sudo pacman -Rns --noconfirm gaze
    fi
    sudo rm -rf -- /etc/gaze /var/cache/gaze /var/lib/gaze >/dev/null 2>&1 || true
    sudo unlink "$gaze_receipt" 2>/dev/null || true
    sudo rmdir "$ownership_dir" 2>/dev/null || true
fi

if [[ -f $face_receipt ]]; then
    unlink "$face_receipt"
fi
rmdir "$state_dir" 2>/dev/null || true

echo "Face ID was removed. Your password is unchanged."
if ((gaze_owned == 0)); then
    echo "Gaze was already present before Face ID setup, so it was kept."
fi
