#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPORT=$($PROJECT_ROOT/bin/doctor --json || true)

jq -e '.schemaVersion == 1' <<<"$REPORT" >/dev/null
jq -e '(.ready | type) == "boolean"' <<<"$REPORT" >/dev/null
jq -e '(.blockers | type) == "array"' <<<"$REPORT" >/dev/null
jq -e '(.omarchy.providerApi | type) == "boolean"' <<<"$REPORT" >/dev/null
jq -e '(.gaze.installed | type) == "boolean"' <<<"$REPORT" >/dev/null
jq -e '(.camera.available | type) == "boolean"' <<<"$REPORT" >/dev/null

# Current Omarchy 4.0.0 has no provider API. The doctor must fail closed.
if jq -e '.omarchy.providerApi == false' <<<"$REPORT" >/dev/null; then
  jq -e '.ready == false' <<<"$REPORT" >/dev/null
fi
