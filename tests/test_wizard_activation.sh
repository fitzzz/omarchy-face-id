#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
project_root=$(cd "$(dirname "$0")/.." && pwd)
client="$project_root/app/GazeClient.cpp"
temporary_dir=$(mktemp -d -t face-id-activation.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

grep -Fq 'holdGazeForPasswordAuthorization' "$client"
grep -Fq 'instead of dismissing the password dialog' "$client"
grep -Fq 'releaseClaim();' "$client"
grep -Fq 'm_lockPluginEnableProcess = process' "$client"
grep -Fq 'handleLockPluginEnableResult' "$client"
if grep -Fq 'QProcess::execute' "$client"; then
    echo "A setup command still blocks the Qt UI thread." >&2
    exit 1
fi
if grep -Fq 'rescanPlugins' "$client"; then
    echo "The redundant synchronous plugin rescan is still present." >&2
    exit 1
fi

install -d "$temporary_dir/config" "$temporary_dir/bin"
install -m 0755 "$project_root/tests/fixtures/omarchy-plugin-enable" \
    "$temporary_dir/bin/pkexec"
install -m 0755 "$project_root/tests/fixtures/omarchy-plugin-enable" \
    "$temporary_dir/bin/omarchy-plugin-enable"
install -m 0755 "$project_root/tests/fixtures/omarchy-shell" \
    "$temporary_dir/bin/omarchy-shell"

PATH="$temporary_dir/bin:$PATH" \
OMARCHY_FACE_ID_CONFIG_ROOT="$temporary_dir/config" \
OMARCHY_FACE_ID_PAM_PATH="$temporary_dir/pam-service" \
OMARCHY_FACE_ID_SKIP_GAZE_AUTH_HOLD=1 \
XDG_STATE_HOME="$temporary_dir/state" \
QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=software \
    "$app_binary" --integration-install-test

plugin_dir="$temporary_dir/config/omarchy/plugins/fitzzz.face-id"
grep -Fxq 'authorization-started' "$temporary_dir/config/authorization-order.log"
grep -Fxq 'authorization-finished' "$temporary_dir/config/authorization-order.log"
if grep -Fq 'plugin-present-too-early' "$temporary_dir/config/authorization-order.log"; then
    echo "plugin reload raced the authorization prompt" >&2
    exit 1
fi
cmp "$project_root/packaging/pam/omarchy-face-id-lock" "$temporary_dir/pam-service"
cmp "$project_root/integration/omarchy-plugin/Service.qml" "$plugin_dir/Service.qml"
cmp "$project_root/integration/omarchy-plugin/manifest.json" "$plugin_dir/manifest.json"
cmp "$project_root/assets/ding.mp3" "$plugin_dir/ding.mp3"
grep -Fq '"id":"fitzzz.face-id"' "$temporary_dir/config/omarchy/shell.json"
[[ $(<"$temporary_dir/config/omarchy/enable-attempts") -eq 3 ]]
