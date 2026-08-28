#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
build_dir="$project_dir/build-appimage"
app_dir="$build_dir/AppDir"
tools_dir="$build_dir/tools"
output_dir="$project_dir/dist"
release_version=$(<"$project_dir/VERSION")

if [[ ! $release_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must contain a semantic version such as 0.5.0." >&2
    exit 1
fi

linuxdeploy_name="linuxdeploy-x86_64.AppImage"
linuxdeploy_url="https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/$linuxdeploy_name"
linuxdeploy_sha256="c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d"

download_tool() {
    local url=$1
    local path=$2
    local expected=$3

    if [[ ! -f "$path" ]]; then
        curl --fail --location --show-error "$url" --output "$path"
    fi
    printf '%s  %s\n' "$expected" "$path" | sha256sum --check --status
    chmod +x "$path"
}

if [[ $(uname -m) != "x86_64" ]]; then
    echo "This packaging script currently supports x86_64 only." >&2
    exit 1
fi

mkdir -p "$tools_dir" "$output_dir"
cmake --fresh -S "$project_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DBUILD_TESTING=ON
cmake --build "$build_dir" --parallel
ctest --test-dir "$build_dir" --output-on-failure

rm -rf -- "$app_dir"
DESTDIR="$app_dir" cmake --install "$build_dir"

download_tool "$linuxdeploy_url" "$tools_dir/$linuxdeploy_name" "$linuxdeploy_sha256"

# Omarchy already ships Qt 6 for its desktop shell. Bundling a second rolling-
# release Qt and multimedia stack causes loader conflicts and makes updates less
# reliable, so this AppImage intentionally contains only this application.
# The executable's compiled QML resources remain inside the binary.
ln -s usr/bin/omarchy-face-id "$app_dir/AppRun"
ln -s usr/share/applications/io.omarchy.FaceId.desktop \
    "$app_dir/io.omarchy.FaceId.desktop"
ln -s usr/share/icons/hicolor/scalable/apps/io.omarchy.FaceId.svg \
    "$app_dir/io.omarchy.FaceId.svg"

tool_extract_dir="$tools_dir/linuxdeploy-extracted"
rm -rf -- "$tool_extract_dir"
mkdir -p "$tool_extract_dir"
(
    cd "$tool_extract_dir"
    "$tools_dir/$linuxdeploy_name" --appimage-extract >/dev/null
)

appimagetool="$tool_extract_dir/squashfs-root/plugins/linuxdeploy-plugin-appimage/usr/bin/appimagetool"
output="$output_dir/Omarchy_Face_ID-${release_version}-x86_64.AppImage"
rm -f -- "$output"
env VERSION="$release_version" "$appimagetool" "$app_dir" "$output"

echo "AppImage $release_version written to $output"
