#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
plugin_source="$project_root/integration/omarchy-plugin"
pam_source="$project_root/packaging/pam/omarchy-face-id-lock"
plugin_target="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/fitzzz.face-id"
face_id_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-face-id"
face_id_config="$face_id_config_dir/config.toml"
pam_target=/etc/pam.d/omarchy-face-id-lock
presence_source=${OMARCHY_FACE_ID_PRESENCE_HELPER_PATH:-}

if [[ -z $presence_source ]]; then
    for candidate in \
        "$project_root/build-native/omarchy-face-id-presence" \
        "$project_root/build-verify/omarchy-face-id-presence" \
        "$project_root/build-appimage/omarchy-face-id-presence"; do
        if [[ -x $candidate ]]; then
            presence_source=$candidate
            break
        fi
    done
fi

if [[ ! -x $presence_source ]]; then
    echo "Build omarchy-face-id-presence before installing the lock integration." >&2
    exit 1
fi

if omarchy-hyprland-session-locked >/dev/null 2>&1; then
    echo "Unlock the computer before installing Omarchy Face ID." >&2
    exit 1
fi

if ! gaze list-faces 2>/dev/null | grep -q 'face for'; then
    echo "No saved face scan was found. Complete enrollment first." >&2
    exit 1
fi

if [[ -e $pam_target ]] && ! cmp -s "$pam_source" "$pam_target"; then
    echo "$pam_target already exists and is not managed by this project." >&2
    exit 1
fi

install -d -m 0755 "$plugin_target"
install -m 0644 "$plugin_source/Service.qml" "$plugin_target/Service.qml"
install -m 0644 "$plugin_source/manifest.json" "$plugin_target/manifest.json"
install -m 0755 "$plugin_source/log-event.sh" "$plugin_target/log-event.sh"
install -m 0644 "$project_root/assets/ding.mp3" "$plugin_target/ding.mp3"
install -m 0755 "$presence_source" "$plugin_target/presence-watcher"

install -d -m 0700 "$face_id_config_dir"
if [[ ! -e $face_id_config ]]; then
    install -m 0600 "$project_root/config/default-config.toml" "$face_id_config"
fi

sudo install -o root -g root -m 0644 "$pam_source" "$pam_target"

omarchy-shell shell rescanPlugins >/dev/null
omarchy-plugin-enable fitzzz.face-id >/dev/null
omarchy-plugin-validate "$plugin_target"

echo "Omarchy Face ID is installed. Lock the computer and look at the camera."
echo "Your password remains available at all times."
