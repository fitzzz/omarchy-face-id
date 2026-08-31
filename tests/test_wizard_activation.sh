#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
project_root=$(cd "$(dirname "$0")/.." && pwd)
client="$project_root/app/GazeClient.cpp"
temporary_dir=$(mktemp -d -t face-id-activation.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

if grep -Fq 'holdGazeForPasswordAuthorization' "$client"; then
    echo "The ineffective Gaze authorization hold is still present." >&2
    exit 1
fi
if grep -Fq 'm_lockPluginEnableAttempts' "$client"; then
    echo "The old blind plugin retry loop is still present." >&2
    exit 1
fi
grep -Fq 'LockActivationPhase::Authorizing' "$client"
grep -Fq 'm_lockActivationDeadline' "$client"
grep -Fq 'Qt::SingleShotConnection' "$client"
grep -Fq 'lockIntegrationStateMatches()' "$client"
grep -Fq 'QStringLiteral("rescanPlugins")' "$client"
if grep -Fq 'QProcess::execute' "$client"; then
    echo "A setup command still blocks the Qt UI thread." >&2
    exit 1
fi
install -d "$temporary_dir/bin"
install -m 0755 "$project_root/tests/fixtures/omarchy-plugin-enable" \
    "$temporary_dir/bin/pkexec"
install -m 0755 "$project_root/tests/fixtures/omarchy-plugin-enable" \
    "$temporary_dir/bin/omarchy-plugin-enable"
install -m 0755 "$project_root/tests/fixtures/omarchy-shell" \
    "$temporary_dir/bin/omarchy-shell"

run_scenario() {
    local mode=$1
    local expected_exit=$2
    local scenario="$temporary_dir/$mode"
    local activation_timeout=4000
    [[ $mode == hang ]] && activation_timeout=350
    install -d "$scenario/config"

    set +e
    PATH="$temporary_dir/bin:$PATH" \
    OMARCHY_FACE_ID_CONFIG_ROOT="$scenario/config" \
    OMARCHY_FACE_ID_PAM_PATH="$scenario/pam-service" \
    OMARCHY_FACE_ID_ACTIVATION_TIMEOUT_MS="$activation_timeout" \
    OMARCHY_FACE_ID_TEST_MODE="$mode" \
    XDG_STATE_HOME="$scenario/state" \
    QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
        "$app_binary" --integration-install-test
    local actual_exit=$?
    set -e
    [[ $actual_exit -eq $expected_exit ]]
}

run_scenario success 0
plugin_dir="$temporary_dir/success/config/omarchy/plugins/fitzzz.face-id"
grep -Fxq 'authorization-started' "$temporary_dir/success/config/authorization-order.log"
grep -Fxq 'authorization-finished' "$temporary_dir/success/config/authorization-order.log"
if grep -Fq 'plugin-present-too-early' "$temporary_dir/success/config/authorization-order.log"; then
    echo "plugin reload raced the authorization prompt" >&2
    exit 1
fi
cmp "$project_root/packaging/pam/omarchy-face-id-lock" "$temporary_dir/success/pam-service"
cmp "$project_root/integration/omarchy-plugin/Service.qml" "$plugin_dir/Service.qml"
cmp "$project_root/integration/omarchy-plugin/manifest.json" "$plugin_dir/manifest.json"
cmp "$project_root/assets/ding.mp3" "$plugin_dir/ding.mp3"
cmp "$project_root/integration/omarchy-plugin/log-event.sh" "$plugin_dir/log-event.sh"
[[ -x $plugin_dir/log-event.sh ]]
presence_helper="$(dirname "$app_binary")/omarchy-face-id-presence"
cmp "$presence_helper" "$plugin_dir/presence-watcher"
[[ -x $plugin_dir/presence-watcher ]]
grep -Fq '"id":"fitzzz.face-id"' "$temporary_dir/success/config/omarchy/shell.json"
[[ $(<"$temporary_dir/success/config/omarchy/enable-attempts") -eq 1 ]]
[[ $(<"$temporary_dir/success/config/omarchy/rescan-attempts") -eq 1 ]]

# A lying exit code cannot override the byte-verified installed PAM file.
run_scenario nonzero-installed 0

# Omarchy may discover a newly written plugin on the next explicit rescan.
run_scenario delayed-discovery 0
[[ $(<"$temporary_dir/delayed-discovery/config/omarchy/rescan-attempts") -eq 2 ]]

# Plugin discovery is bounded and returns the UI to a retryable state.
run_scenario never-discover 1
[[ $(<"$temporary_dir/never-discover/config/omarchy/rescan-attempts") -eq 3 ]]

# Denial and a vanished authorization prompt both return the UI to a retryable state.
run_scenario denied 1
[[ ! -e $temporary_dir/denied/config/omarchy/plugins/fitzzz.face-id ]]
run_scenario hang 1
[[ ! -e $temporary_dir/hang/config/omarchy/plugins/fitzzz.face-id ]]
