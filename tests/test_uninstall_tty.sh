#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
temporary_dir=$(mktemp -d -t omarchy-face-id-uninstall-tty.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

app_command=$(printf '%q' "$app_binary")
output=$(printf 'n\n' | \
    XDG_STATE_HOME="$temporary_dir/state" \
    OMARCHY_FACE_ID_PLUGIN_TARGET="$temporary_dir/plugin" \
    OMARCHY_FACE_ID_PAM_PATH="$temporary_dir/pam" \
    OMARCHY_FACE_ID_OWNERSHIP_DIR="$temporary_dir/ownership" \
    OMARCHY_FACE_ID_SKIP_LOCK_CHECK=1 \
    script --quiet --return --command "$app_command --uninstall" /dev/null)

grep -Fq 'Continue? [y/N]' <<<"$output"
if grep -Fq 'Run interactively or pass --yes.' <<<"$output"; then
    echo "The AppImage wrapper did not forward its terminal input." >&2
    exit 1
fi
