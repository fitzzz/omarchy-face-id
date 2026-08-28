#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
project_root=$(cd "$(dirname "$0")/.." && pwd)
temporary_dir=$(mktemp -d -t face-id-activation.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

install -d "$temporary_dir/config" "$temporary_dir/bin"
install -m 0644 "$project_root/packaging/pam/omarchy-face-id-lock" "$temporary_dir/pam-service"
install -m 0755 "$project_root/tests/fixtures/omarchy-plugin-enable" \
    "$temporary_dir/bin/omarchy-plugin-enable"
install -m 0755 "$project_root/tests/fixtures/omarchy-shell" \
    "$temporary_dir/bin/omarchy-shell"

PATH="$temporary_dir/bin:$PATH" \
OMARCHY_FACE_ID_CONFIG_ROOT="$temporary_dir/config" \
OMARCHY_FACE_ID_PAM_PATH="$temporary_dir/pam-service" \
QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=software \
    "$app_binary" --integration-install-test

plugin_dir="$temporary_dir/config/omarchy/plugins/fitzzz.face-id"
cmp "$project_root/integration/omarchy-plugin/Service.qml" "$plugin_dir/Service.qml"
cmp "$project_root/integration/omarchy-plugin/manifest.json" "$plugin_dir/manifest.json"
