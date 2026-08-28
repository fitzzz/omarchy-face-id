#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary_dir=$(mktemp -d -t face-id-diagnostics.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

XDG_STATE_HOME="$temporary_dir/state" \
QT_QPA_PLATFORM=offscreen \
QT_QUICK_BACKEND=software \
    "$app_binary" --smoke-test >"$temporary_dir/app.log" 2>&1

XDG_STATE_HOME="$temporary_dir/state" \
    "$project_root/integration/omarchy-plugin/log-event.sh" \
        subscriber_started info 12345678-1234-1234-1234-123456789abc
XDG_STATE_HOME="$temporary_dir/state" \
    "$project_root/integration/omarchy-plugin/log-event.sh" \
        attempt_started info 12345678-1234-1234-1234-123456789abc generation=1

diagnostics="$temporary_dir/state/omarchy-face-id/diagnostics.jsonl"
[[ -s $diagnostics ]]
[[ $(stat -c '%a' "$diagnostics") == 600 ]]

jq -e -c '
    .schema == "omarchy.face-id.diagnostics.event"
    and .schema_version == 1
    and (.timestamp_utc | type == "string")
    and (.session_id | test("^[0-9a-f-]{36}$"))
    and (.sequence | type == "number")
    and (.level | IN("debug", "info", "warning", "error"))
    and (.component | test("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$"))
    and (.event | test("^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$"))
    and (.attributes | type == "object")
' "$diagnostics" >/dev/null

grep -Fq '"event":"session_started"' "$diagnostics"
grep -Fq '"event":"session_stopped"' "$diagnostics"
grep -Fq '"component":"camera.inventory"' "$diagnostics"
grep -Fq '"event":"attempt_started"' "$diagnostics"
grep -Fq '"event":"camera_selection_observed"' "$diagnostics"

if grep -Eiq '(/home/|/dev/|@|"(user|username|path|device|command|output|message|frame|image|jpeg|embedding|biometric|token|password|secret|email|hostname|address|ip)"[[:space:]]*:)' \
    "$diagnostics"; then
    echo "Diagnostics contain a forbidden identifying or biometric field." >&2
    exit 1
fi

if [[ -n ${USER:-} ]] && grep -Fq "$USER" "$diagnostics"; then
    echo "Diagnostics contain the current account name." >&2
    exit 1
fi
