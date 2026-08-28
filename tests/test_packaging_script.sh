#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$project_dir/scripts/build-appimage.sh"

bash -n "$script"
grep -Fq 'ln -s usr/bin/omarchy-face-id "$app_dir/AppRun"' "$script"
grep -Fq 'linuxdeploy-plugin-appimage/usr/bin/appimagetool' "$script"
if grep -Fq -- '--plugin qt' "$script"; then
    echo "The Omarchy AppImage must not bundle a second Qt runtime." >&2
    exit 1
fi
