#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
project_root=$(cd "$(dirname "$0")/.." && pwd)
temporary_dir=$(mktemp -d -t face-id-config.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

run_app() {
    OMARCHY_FACE_ID_CONFIG_HOME="$temporary_dir/config" \
    XDG_STATE_HOME="$temporary_dir/state" \
    QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
        "$app_binary" --smoke-test
}

run_app
config="$temporary_dir/config/omarchy-face-id/config.toml"
cmp "$project_root/config/default-config.toml" "$config"
[[ $(stat -c '%a' "$config") == 600 ]]
grep -Fxq 'presence_mode = "low_power"' "$config"

sed -i 's/presence_mode = "low_power"/presence_mode = "on_activity"/' "$config"
run_app
grep -Fxq 'presence_mode = "on_activity"' "$config"

mkdir -p "$temporary_dir/symlink-config/omarchy-face-id"
printf '%s\n' 'sentinel' > "$temporary_dir/sentinel"
ln -s "$temporary_dir/sentinel" \
    "$temporary_dir/symlink-config/omarchy-face-id/config.toml"
OMARCHY_FACE_ID_CONFIG_HOME="$temporary_dir/symlink-config" \
XDG_STATE_HOME="$temporary_dir/symlink-state" \
QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=software \
    "$app_binary" --smoke-test
grep -Fxq 'sentinel' "$temporary_dir/sentinel"
