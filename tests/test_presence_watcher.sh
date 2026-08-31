#!/usr/bin/env bash

set -euo pipefail

presence_binary=${1:?presence binary is required}
temporary_dir=$(mktemp -d -t face-id-presence.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

cat > "$temporary_dir/config.toml" <<'EOF'
schema_version = 1

[lock_screen]
presence_mode = "low_power"
motion_sensitivity = "high"
EOF

OMARCHY_FACE_ID_PRESENCE_TEST_SOURCE='videotestsrc is-live=true pattern=ball animation-mode=frames' \
OMARCHY_FACE_ID_GAZE_CONFIG="$temporary_dir/missing-gaze.toml" \
XDG_STATE_HOME="$temporary_dir/moving-state" \
    "$presence_binary" --config "$temporary_dir/config.toml" --timeout-ms 6000

set +e
OMARCHY_FACE_ID_PRESENCE_TEST_SOURCE='videotestsrc is-live=true pattern=black' \
OMARCHY_FACE_ID_GAZE_CONFIG="$temporary_dir/missing-gaze.toml" \
XDG_STATE_HOME="$temporary_dir/static-state" \
    "$presence_binary" --config "$temporary_dir/config.toml" --timeout-ms 3500
static_exit=$?
set -e
[[ $static_exit -eq 4 ]]

moving_log="$temporary_dir/moving-state/omarchy-face-id/diagnostics.jsonl"
static_log="$temporary_dir/static-state/omarchy-face-id/diagnostics.jsonl"
grep -Fq '"component":"presence.watcher"' "$moving_log"
grep -Fq '"event":"motion_detected"' "$moving_log"
grep -Fq '"result_code":4' "$static_log"

if rg -n 'frame|image|pixel|embedding|username|device_path' "$moving_log" "$static_log"; then
    echo "Presence diagnostics must not contain camera frames or identity data." >&2
    exit 1
fi
