#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
project_root=$(cd "$(dirname "$0")/.." && pwd)
client="$project_root/app/GazeClient.cpp"
main_qml="$project_root/qml/Main.qml"
consent_qml="$project_root/elevation/ConsentPrompt.qml"
temporary_dir=$(mktemp -d -t face-id-activation.XXXXXX)
cleanup() {
    local status=$?
    if [[ $status -ne 0 && ${OMARCHY_FACE_ID_KEEP_TEST_ROOT:-0} == 1 ]]; then
        printf 'Preserved failed activation root: %s\n' "$temporary_dir" >&2
    else
        rm -rf -- "$temporary_dir"
    fi
}
trap cleanup EXIT

# This suite may only use its fake roots and fake commands. Refuse to run if
# the sandbox cannot be established; no sudo, PAM, systemd, or live Omarchy
# path is ever invoked by these scenarios.
[[ $temporary_dir == /tmp/face-id-activation.* ]]
[[ ! -e $temporary_dir/etc ]]
[[ ! -e $temporary_dir/usr ]]

if grep -Fq 'm_lockShellVerificationPasses < 5' "$client"; then
    echo "Repeated readiness polling is still present." >&2
    exit 1
fi
grep -Fq 'stageAndActivateUserPlugin' "$client"
grep -Fq 'rollbackUserPluginActivation' "$client"
grep -Fq 'OMARCHY_FACE_ID_ALLOW_DOWNGRADE' "$client"
grep -Fq 'used_restart_fallback' "$client"
grep -Fq 'files_installed' "$client"
grep -Fq 'live_active' "$client"
grep -Fq 'command_deadline_reached' "$client"
grep -Fq 'QProcess::startDetached(m_lockShellRestartCommand)' "$client"
if rg -U 'shell_restart[\s\S]{0,300}armProcessDeadline' "$client"; then
    echo "The updater must never kill an Omarchy Shell restart." >&2
    exit 1
fi
if grep -Fq 'QProcess::execute' "$client"; then
    echo "A setup command still blocks the Qt UI thread." >&2
    exit 1
fi
grep -Fq 'Installing Face ID components…' "$main_qml"
grep -Fq 'Reloading Omarchy Shell…' "$client"
grep -Fq 'Waiting for Omarchy Shell…' "$client"
grep -Fq 'height: root.stableContentHeight' "$consent_qml"
grep -Fq 'Math.max(decisionActions.implicitHeight, cancelAction.implicitHeight)' \
    "$consent_qml"
if rg -U 'startLockPluginRescan\(\)[\s\S]{0,2200}armProcessDeadline' "$client"; then
    echo "The updater must let Omarchy Shell own its rescan lifetime." >&2
    exit 1
fi

install -d "$temporary_dir/bin"
install -m 0755 "$project_root/tests/fixtures/activation-plugin-enable" \
    "$temporary_dir/bin/pkexec"
install -m 0755 "$project_root/tests/fixtures/activation-plugin-enable" \
    "$temporary_dir/bin/omarchy-plugin-enable"
install -m 0755 "$project_root/tests/fixtures/omarchy-shell" \
    "$temporary_dir/bin/omarchy-shell"
install -m 0755 "$project_root/tests/fixtures/omarchy-shell" \
    "$temporary_dir/bin/omarchy-restart-shell"

candidate_version=$($app_binary --version | awk '{print $NF}')

run_scenario() {
    local mode=$1
    local expected_exit=$2
    shift 2
    local scenario="$temporary_dir/$mode"
    local activation_timeout=2500
    local fallback_timeout=300
    [[ $mode == hang ]] && activation_timeout=450
    [[ $mode == restart-slow-ready ]] && fallback_timeout=1200
    install -d "$scenario/config"

    set +e
    PATH="$temporary_dir/bin:$PATH" \
    OMARCHY_FACE_ID_CONFIG_ROOT="$scenario/config" \
    OMARCHY_FACE_ID_PAM_PATH="$scenario/pam-service" \
    OMARCHY_FACE_ID_ACTIVATION_TIMEOUT_MS="$activation_timeout" \
    OMARCHY_FACE_ID_COMMAND_TIMEOUT_MS=120 \
    OMARCHY_FACE_ID_VERIFY_TIMEOUT_MS=120 \
    OMARCHY_FACE_ID_FALLBACK_VERIFY_TIMEOUT_MS="$fallback_timeout" \
    OMARCHY_FACE_ID_TEST_MODE="$mode" \
    XDG_STATE_HOME="$scenario/state" \
    GSETTINGS_BACKEND=memory \
    QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software \
        "$app_binary" --integration-install-test "$@"
    local actual_exit=$?
    set -e
    [[ $actual_exit -eq $expected_exit ]]
}

assert_no_transaction_debris() {
    local scenario=$1
    local transaction_root="$temporary_dir/$scenario/config/omarchy/.face-id-transactions"
    if [[ -d $transaction_root ]] \
        && find "$transaction_root" -mindepth 1 -print -quit | grep -q .; then
        echo "Activation transaction debris remained for $scenario." >&2
        exit 1
    fi
}

run_scenario success 0
plugin_dir="$temporary_dir/success/config/omarchy/plugins/fitzzz.face-id"
cmp "$project_root/packaging/pam/omarchy-face-id-lock" "$temporary_dir/success/pam-service"
cmp "$project_root/integration/omarchy-plugin/Service.qml" "$plugin_dir/Service.qml"
    cmp "$project_root/integration/omarchy-plugin/LockState.js" "$plugin_dir/LockState.js"
    cmp "$project_root/integration/omarchy-plugin/FaceIdIndicator.qml" \
        "$plugin_dir/FaceIdIndicator.qml"
cmp "$project_root/integration/omarchy-plugin/manifest.json" "$plugin_dir/manifest.json"
cmp "$project_root/assets/ding.mp3" "$plugin_dir/ding.mp3"
cmp "$project_root/integration/omarchy-plugin/log-event.sh" "$plugin_dir/log-event.sh"
grep -Fxq "$candidate_version" "$plugin_dir/.omarchy-face-id-version"
[[ ! -e $plugin_dir/ActionButton.qml ]]
[[ $(<"$temporary_dir/success/config/omarchy/enable-attempts") -eq 1 ]]
[[ $(<"$temporary_dir/success/config/omarchy/rescan-attempts") -eq 1 ]]
[[ $(<"$temporary_dir/success/config/omarchy/verification-attempts") -eq 1 ]]
[[ ! -e $temporary_dir/success/config/omarchy/restart-attempts ]]
grep -Fq '"files_installed":true' \
    "$temporary_dir/success/state/omarchy-face-id/diagnostics.jsonl"
grep -Fq '"live_active":true' \
    "$temporary_dir/success/state/omarchy-face-id/diagnostics.jsonl"
assert_no_transaction_debris success

# A supported rescan can take longer than the updater's former 1.5-second
# deadline. Let omarchy-shell finish it instead of forcing a shell restart.
run_scenario rescan-slow-ready 0
[[ -e $temporary_dir/rescan-slow-ready/config/omarchy/rescan-complete ]]
[[ ! -e $temporary_dir/rescan-slow-ready/config/omarchy/restart-attempts ]]

# Core shell readiness and plugin-handler readiness are distinct states. One
# failed hot-reload check may use exactly one restart and one fallback check.
run_scenario core-before-handler 0
[[ $(<"$temporary_dir/core-before-handler/config/omarchy/restart-attempts") -eq 1 ]]
[[ $(<"$temporary_dir/core-before-handler/config/omarchy/verification-attempts") -eq 2 ]]

run_scenario fallback-delayed-ready 0
[[ $(<"$temporary_dir/fallback-delayed-ready/config/omarchy/restart-attempts") -eq 1 ]]
[[ $(<"$temporary_dir/fallback-delayed-ready/config/omarchy/verification-attempts") -eq 2 ]]

# A nonzero restart result cannot override a verified live postcondition.
run_scenario restart-nonzero-ready 0
grep -Fq '"event":"shell_restart_dispatched","level":"info"' \
    "$temporary_dir/restart-nonzero-ready/state/omarchy-face-id/diagnostics.jsonl"

# A restart may legitimately outlive the updater's old four-second budget.
# It runs detached, is never killed, and readiness is observed afterward.
run_scenario restart-slow-ready 0
[[ -e $temporary_dir/restart-slow-ready/config/omarchy/restart-finished ]]

# A readiness failure is nonzero and restores the exact previous directory.
rollback_root="$temporary_dir/restart-not-ready/config/omarchy/plugins/fitzzz.face-id"
install -d "$rollback_root" "$temporary_dir/restart-not-ready/config/omarchy"
printf '%s\n' 'old-plugin' > "$rollback_root/sentinel"
printf '%s\n' '{"version":1,"plugins":[{"id":"fitzzz.face-id"}]}' \
    > "$temporary_dir/restart-not-ready/config/omarchy/shell.json"
run_scenario restart-not-ready 1
grep -Fxq old-plugin "$rollback_root/sentinel"
[[ ! -e $rollback_root/Service.qml ]]
grep -Fq 'plugin_files_rolled_back' \
    "$temporary_dir/restart-not-ready/state/omarchy-face-id/diagnostics.jsonl"
grep -Fq '"live_active":false' \
    "$temporary_dir/restart-not-ready/state/omarchy-face-id/diagnostics.jsonl"
assert_no_transaction_debris restart-not-ready

# Hung commands are killed by phase deadlines and cannot leave a fresh plugin.
run_scenario verification-hang 1
[[ ! -e $temporary_dir/verification-hang/config/omarchy/plugins/fitzzz.face-id ]]
grep -Fq '"event":"command_deadline_reached"' \
    "$temporary_dir/verification-hang/state/omarchy-face-id/diagnostics.jsonl"

# Same-version reruns are repairs and replace stale files as one directory.
repair_root="$temporary_dir/same-version-repair/config/omarchy/plugins/fitzzz.face-id"
install -d "$repair_root" "$temporary_dir/same-version-repair/config/omarchy"
printf '%s\n' "$candidate_version" > "$repair_root/.omarchy-face-id-version"
printf '%s\n' stale > "$repair_root/Service.qml"
printf '%s\n' stale > "$repair_root/ActionButton.qml"
printf '%s\n' '{"version":1,"plugins":[{"id":"fitzzz.face-id"}]}' \
    > "$temporary_dir/same-version-repair/config/omarchy/shell.json"
run_scenario same-version-repair 0
cmp "$project_root/integration/omarchy-plugin/Service.qml" "$repair_root/Service.qml"
[[ ! -e $repair_root/ActionButton.qml ]]

# A newer receipt blocks all writes unless the explicit developer override is used.
newer_root="$temporary_dir/downgrade-blocked/config/omarchy/plugins/fitzzz.face-id"
install -d "$newer_root"
printf '%s\n' '99.0.0' > "$newer_root/.omarchy-face-id-version"
printf '%s\n' newer > "$newer_root/sentinel"
run_scenario downgrade-blocked 1
grep -Fxq newer "$newer_root/sentinel"
[[ ! -e $temporary_dir/downgrade-blocked/config/authorization-order.log ]]
grep -Fq '"event":"downgrade_blocked"' \
    "$temporary_dir/downgrade-blocked/state/omarchy-face-id/diagnostics.jsonl"

override_root="$temporary_dir/downgrade-allowed/config/omarchy/plugins/fitzzz.face-id"
install -d "$override_root"
printf '%s\n' '99.0.0' > "$override_root/.omarchy-face-id-version"
printf '%s\n' newer > "$override_root/sentinel"
run_scenario downgrade-allowed 0 --allow-downgrade
grep -Fxq "$candidate_version" "$override_root/.omarchy-face-id-version"
[[ ! -e $override_root/sentinel ]]

# Authorization denial, disappearance, and a lying nonzero exit remain bounded.
run_scenario nonzero-installed 0
run_scenario denied 1
[[ ! -e $temporary_dir/denied/config/omarchy/plugins/fitzzz.face-id ]]
run_scenario hang 1
[[ ! -e $temporary_dir/hang/config/omarchy/plugins/fitzzz.face-id ]]
