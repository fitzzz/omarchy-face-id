#!/usr/bin/env bash

set -euo pipefail

bridge=${1:?elevation helper is required}
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$project_root/elevation/main.cpp"
temporary_dir=$(mktemp -d -t face-id-elevation.XXXXXX)
cleanup() {
    local status=$?
    if [[ -n ${hyprland_socket_pid:-} ]]; then
        kill -KILL "$hyprland_socket_pid" 2>/dev/null || true
        wait "$hyprland_socket_pid" 2>/dev/null || true
    fi
    if [[ -n ${desktop_socket_pid:-} ]]; then
        kill -KILL "$desktop_socket_pid" 2>/dev/null || true
        wait "$desktop_socket_pid" 2>/dev/null || true
    fi
    if [[ $status -ne 0 && ${OMARCHY_FACE_ID_KEEP_TEST_ROOT:-0} == 1 ]]; then
        printf 'Preserved failed elevation root: %s\n' "$temporary_dir" >&2
    else
        rm -rf -- "$temporary_dir"
    fi
}
trap cleanup EXIT

# Hard guard: every test-only path must stay under this invocation's temp root.
[[ $temporary_dir == /tmp/face-id-elevation.* ]]
[[ $bridge != /usr/* && $bridge != /bin/* && $bridge != /sbin/* ]]

export OMARCHY_FACE_ID_ELEVATION_ALLOW_UNPRIVILEGED=1
export OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR="$temporary_dir"
export OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS=5000
export QT_QPA_PLATFORM=offscreen
export QT_QUICK_BACKEND=software
export XDG_STATE_HOME="$temporary_dir/state"

# Model Hyprland's production boundary without touching the running
# compositor. The helper must target its own exact window address, then float,
# resize, center, and raise only that window.
cat >"$temporary_dir/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == clients && ${2:-} == -j ]]; then
    if [[ -n ${OMARCHY_FACE_ID_ELEVATION_EXPECT_SIGNATURE:-} \
        && ${HYPRLAND_INSTANCE_SIGNATURE:-} != \
            "$OMARCHY_FACE_ID_ELEVATION_EXPECT_SIGNATURE" ]]; then
        exit 1
    fi
    printf '[{"pid":%s,"class":"io.omarchy.FaceId.Elevation","address":"0xabc123","floating":false}]\n' \
        "$OMARCHY_FACE_ID_ELEVATION_PROMPT_PID"
    exit 0
fi
printf '%s\n' "$*" >>"$OMARCHY_FACE_ID_ELEVATION_HYPRCTL_LOG"
EOF
chmod +x "$temporary_dir/hyprctl"
export OMARCHY_FACE_ID_ELEVATION_TEST_HYPRCTL="$temporary_dir/hyprctl"
export OMARCHY_FACE_ID_ELEVATION_HYPRCTL_LOG="$temporary_dir/hyprctl.log"
: >"$OMARCHY_FACE_ID_ELEVATION_HYPRCTL_LOG"

# Test responses must drive the production prompt after QML has created its
# root object. A synthetic test-only prompt would let broken embedded QML pass.
if rg -n 'runSyntheticPrompt' "$source_file"; then
    echo 'Elevation tests must not bypass the production QML prompt.' >&2
    exit 1
fi
grep -Fq 'qrc:/elevation/ConsentPrompt.qml' "$source_file"
if ! rg -U 'deadline = testMode\(\)[\s\S]{0,180}: 0;' "$source_file"; then
    echo 'The production approval prompt still has a decision deadline.' >&2
    exit 1
fi
root_check_line=$(grep -n -m1 'engine\.rootObjects()\.isEmpty()' "$source_file" | cut -d: -f1)
test_response_line=$(grep -n -m1 'OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE' "$source_file" | cut -d: -f1)
overlay_rule_line=$(grep -n -m1 '!prepareOverlayRule' "$source_file" | cut -d: -f1)
qml_load_line=$(grep -n -m1 'engine\.load(QUrl' "$source_file" | cut -d: -f1)
if [[ -z $root_check_line || -z $test_response_line \
    || $test_response_line -le $root_check_line ]]; then
    echo 'Test auto-response must be read only after the production QML root object exists.' >&2
    exit 1
fi
if [[ -z $overlay_rule_line || -z $qml_load_line \
    || $overlay_rule_line -ge $qml_load_line ]]; then
    echo 'The floating rule must be ready before QML can map the prompt.' >&2
    exit 1
fi

expect_status() {
    local expected=$1
    local behavior=$2
    set +e
    OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE=$behavior "$bridge" request
    local status=$?
    set -e
    if [[ $status -ne $expected ]]; then
        printf 'behavior %s returned %s, expected %s\n' \
            "$behavior" "$status" "$expected" >&2
        exit 1
    fi
}

require_fixed_text() {
    local expected=$1
    local path=$2
    local description=$3
    if ! grep -Fq "$expected" "$path"; then
        printf 'missing %s in %s\n' "$description" "$path" >&2
        sed -n '1,160p' "$path" >&2
        exit 1
    fi
}

expect_status 0 approve
expect_status 10 deny
expect_status 20 close
expect_status 20 malformed
expect_status 20 crash
expect_status 20 hang
export OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS=150
expect_status 20 no-ready
export OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT=hang
expect_status 10 cancel-checking
unset OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT
export OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS=5000

# Approval keeps the prompt alive while the verifier runs. Every verifier
# failure returns to password, and a stuck verifier is killed at its phase cap.
export OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT=failure
expect_status 20 approve
export OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT=hang
export OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS=150
expect_status 20 approve
export OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS=5000
unset OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT

require_fixed_text \
    'eval if _G.omarchy_face_id_elevation_rule == nil then' \
    "$OMARCHY_FACE_ID_ELEVATION_HYPRCTL_LOG" 'creation-time overlay rule'
require_fixed_text \
    'dispatch hl.dsp.window.float({ window = "address:0xabc123", action = "toggle" })' \
    "$OMARCHY_FACE_ID_ELEVATION_HYPRCTL_LOG" 'float dispatch'
require_fixed_text \
    'dispatch hl.dsp.window.resize({ window = "address:0xabc123", x = 560, y = 500 })' \
    "$OMARCHY_FACE_ID_ELEVATION_HYPRCTL_LOG" 'resize dispatch'
require_fixed_text \
    'dispatch hl.dsp.window.center({ window = "address:0xabc123" })' \
    "$OMARCHY_FACE_ID_ELEVATION_HYPRCTL_LOG" 'center dispatch'
require_fixed_text \
    'dispatch hl.dsp.window.alter_zorder({ window = "address:0xabc123", mode = "top" })' \
    "$OMARCHY_FACE_ID_ELEVATION_HYPRCTL_LOG" 'raise dispatch'

# sudo does not guarantee that desktop variables survive into PAM. The helper
# must discover a socket owned by the verified local user inside that user's
# private runtime directory, then pass the validated endpoint to the prompt.
desktop_runtime="$temporary_dir/desktop-runtime"
desktop_socket="$desktop_runtime/wayland-7"
hyprland_signature=test-signature_123
hyprland_runtime="$desktop_runtime/hypr/$hyprland_signature"
hyprland_socket="$hyprland_runtime/.socket.sock"
mkdir -m 0700 "$desktop_runtime"
mkdir -m 0700 -p "$hyprland_runtime"
printf '%s\n%s\n' "$$" wayland-7 >"$hyprland_runtime/hyprland.lock"
chmod 0644 "$hyprland_runtime/hyprland.lock"
socat UNIX-LISTEN:"$desktop_socket" OPEN:/dev/null &
desktop_socket_pid=$!
socat UNIX-LISTEN:"$hyprland_socket" OPEN:/dev/null &
hyprland_socket_pid=$!
for _ in {1..50}; do
    [[ -S $desktop_socket && -S $hyprland_socket ]] && break
    sleep 0.02
done
[[ -S $desktop_socket ]]
[[ -S $hyprland_socket ]]
unset XDG_RUNTIME_DIR WAYLAND_DISPLAY
unset HYPRLAND_INSTANCE_SIGNATURE
export OMARCHY_FACE_ID_ELEVATION_TEST_DESKTOP_RUNTIME="$desktop_runtime"
export OMARCHY_FACE_ID_ELEVATION_TEST_DESKTOP_DISPLAY=wayland-7
export OMARCHY_FACE_ID_ELEVATION_EXPECT_SIGNATURE="$hyprland_signature"
expect_status 0 require-desktop
chmod 0777 "$desktop_runtime/hypr"
expect_status 20 require-desktop
chmod 0700 "$desktop_runtime/hypr"
unset OMARCHY_FACE_ID_ELEVATION_TEST_DESKTOP_RUNTIME
unset OMARCHY_FACE_ID_ELEVATION_TEST_DESKTOP_DISPLAY
unset OMARCHY_FACE_ID_ELEVATION_EXPECT_SIGNATURE
kill -KILL "$hyprland_socket_pid"
wait "$hyprland_socket_pid" 2>/dev/null || true
hyprland_socket_pid=
rm -f -- "$hyprland_socket"
kill -KILL "$desktop_socket_pid"
wait "$desktop_socket_pid" 2>/dev/null || true
desktop_socket_pid=
rm -f -- "$desktop_socket"

# One root-owned coordinator request is allowed at a time. Hold its exact lock
# deterministically: a competing request must immediately fall back to password
# without relying on process-startup timing under a loaded test runner.
exec 8>"$temporary_dir/single-flight.lock"
flock -x 8
expect_status 20 approve
flock -u 8
exec 8>&-

# The trusted request channel is an inherited socketpair. There must be no
# public user-runtime socket that another same-UID process can replace.
if find "$temporary_dir" -type s -print -quit | grep -q .; then
    echo 'Elevation helper exposed a filesystem authorization socket.' >&2
    exit 1
fi

[[ $("$bridge" --version) == 'Omarchy Face ID elevation helper 3' ]]
grep -aFq 'Omarchy Face ID elevation bridge 1' "$bridge"
if "$bridge" checking || "$bridge" unlocked || "$bridge" rejected; then
    echo 'Obsolete diagnostic callback commands must not remain in the helper.' >&2
    exit 1
fi

diagnostics="$temporary_dir/state/omarchy-face-id/diagnostics.jsonl"
[[ -s $diagnostics ]]
require_fixed_text '"component":"elevation.authentication"' "$diagnostics" \
    'elevation diagnostics component'
require_fixed_text '"event":"consent_prompt_opened"' "$diagnostics" \
    'prompt-opened diagnostic'
require_fixed_text '"event":"consent_approved"' "$diagnostics" \
    'approval diagnostic'
require_fixed_text '"event":"consent_declined"' "$diagnostics" \
    'decline diagnostic'
require_fixed_text '"event":"face_verification_started"' "$diagnostics" \
    'checking diagnostic'
require_fixed_text '"event":"face_verification_succeeded"' "$diagnostics" \
    'success diagnostic'
require_fixed_text '"event":"face_verification_unavailable"' "$diagnostics" \
    'fallback diagnostic'
if grep -Eqi 'programmer|password|command|/home/|/dev/' "$diagnostics"; then
    echo 'Elevation diagnostics contain identifying or sensitive data.' >&2
    exit 1
fi
