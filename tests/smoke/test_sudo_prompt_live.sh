#!/usr/bin/env bash

set -euo pipefail

# This intentional manual smoke test exercises the production sudo-prompt UI
# directly. It does not invoke sudo, install PAM files, or alter system state.
if [[ ${OMARCHY_FACE_ID_RUN_LIVE_ELEVATION_SMOKE:-} != 1 ]]; then
    echo 'Set OMARCHY_FACE_ID_RUN_LIVE_ELEVATION_SMOKE=1 to open the live elevation prompt.' >&2
    exit 2
fi

bridge=${1:?usage: test_sudo_prompt_live.sh PATH_TO_ELEVATION_HELPER}
if [[ ! -x $bridge ]]; then
    printf 'Elevation helper is not executable: %s\n' "$bridge" >&2
    exit 2
fi
if [[ -z ${XDG_RUNTIME_DIR:-} || -z ${WAYLAND_DISPLAY:-} ]]; then
    echo 'Run this smoke test from an active Wayland desktop session.' >&2
    exit 2
fi

temporary_dir=$(mktemp -d -t face-id-live-elevation.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

export OMARCHY_FACE_ID_ELEVATION_ALLOW_UNPRIVILEGED=1
export OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR="$temporary_dir"
export XDG_STATE_HOME="$temporary_dir/state"
unset OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE

set +e
"$bridge" request
status=$?
set -e

case $status in
    0) echo 'Live elevation prompt approved.' ;;
    10) echo 'Live elevation prompt declined.' ;;
    20) echo 'Live elevation prompt closed or unavailable.' ;;
    *) printf 'Live elevation prompt returned unexpected status %s.\n' "$status" >&2; exit 1 ;;
esac
