#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$project_dir/scripts/build-appimage.sh"
release_version=$(<"$project_dir/VERSION")

bash -n "$script"
if [[ -e $project_dir/scripts/install-lock-integration.sh ]]; then
    echo 'The obsolete standalone lock-integration installer must not be packaged.' >&2
    exit 1
fi
[[ $release_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
grep -Fq 'ln -s usr/bin/omarchy-face-id "$app_dir/AppRun"' "$script"
grep -Fq 'linuxdeploy-plugin-appimage/usr/bin/appimagetool' "$script"
grep -Fq 'Omarchy_Face_ID-${release_version}-x86_64.AppImage' "$script"
grep -Fq 'legacy_output="$output_dir/Omarchy_Face_ID-x86_64.AppImage"' "$script"
grep -Fq 'rm -f -- "$legacy_output"' "$script"
grep -Fq "VERSION $release_version" "$project_dir/CMakeLists.txt" && {
    echo "CMake must read the release version from VERSION instead of duplicating it." >&2
    exit 1
}
grep -Fq "\"version\": \"$release_version\"" \
    "$project_dir/integration/omarchy-plugin/manifest.json"
grep -Fq "## $release_version -" "$project_dir/CHANGELOG.md"
grep -Fq 'install(PROGRAMS' "$project_dir/CMakeLists.txt"
grep -Fq 'scripts/install-gaze-arch.sh' "$project_dir/CMakeLists.txt"
grep -Fq 'scripts/uninstall.sh' "$project_dir/CMakeLists.txt"
grep -Fq 'trustedSystemPayload(installerPath)' "$project_dir/app/GazeClient.cpp"
if rg -q 'omarchy-face-id-(installer|elevation|consent)\.XXXXXX' \
    "$project_dir/app/GazeClient.cpp"; then
    echo "Privileged AppImage payloads must not be copied through mutable temp files." >&2
    exit 1
fi
if grep -Fq -- '--plugin qt' "$script"; then
    echo "The Omarchy AppImage must not bundle a second Qt runtime." >&2
    exit 1
fi
