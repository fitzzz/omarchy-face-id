#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$project_dir/scripts/build-appimage.sh"
release_version=$(<"$project_dir/VERSION")

bash -n "$script"
[[ $release_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
grep -Fq 'ln -s usr/bin/omarchy-face-id "$app_dir/AppRun"' "$script"
grep -Fq 'linuxdeploy-plugin-appimage/usr/bin/appimagetool' "$script"
grep -Fq 'Omarchy_Face_ID-${release_version}-x86_64.AppImage' "$script"
grep -Fq "VERSION $release_version" "$project_dir/CMakeLists.txt" && {
    echo "CMake must read the release version from VERSION instead of duplicating it." >&2
    exit 1
}
grep -Fq "\"version\": \"$release_version\"" \
    "$project_dir/integration/omarchy-plugin/manifest.json"
grep -Fq "## $release_version -" "$project_dir/CHANGELOG.md"
if grep -Fq -- '--plugin qt' "$script"; then
    echo "The Omarchy AppImage must not bundle a second Qt runtime." >&2
    exit 1
fi
