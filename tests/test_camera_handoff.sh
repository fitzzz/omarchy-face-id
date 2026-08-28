#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
main_qml="$project_dir/qml/Main.qml"

# Real Gaze enrollment must never overlap the Qt camera pipeline. The preview
# may remain active on the enrollment page only when Gaze is unavailable.
grep -Fq 'readonly property bool localPreviewActive: !gazeClient.installed' "$main_qml"
grep -Fq 'id: localCameraLoader' "$main_qml"
grep -Fq 'active: root.localPreviewActive && root.cameraPresent' "$main_qml"
grep -Fq 'camera: localCameraLoader.item' "$main_qml"

if grep -Fq '(!enrollmentStarted || !realEnrollment)' "$main_qml"; then
    echo "Qt camera ownership still overlaps the real enrollment page." >&2
    exit 1
fi

app_binary=${OMARCHY_FACE_UNLOCK_BINARY:-"$PWD/omarchy-face-unlock"}
if [[ -x "$app_binary" ]]; then
    temporary_dir=$(mktemp -d -t face-unlock-theme-test.XXXXXX)
    app_pid=""
    cleanup() {
        if [[ -n "$app_pid" ]]; then
            kill "$app_pid" 2>/dev/null || true
            wait "$app_pid" 2>/dev/null || true
        fi
        rm -rf -- "$temporary_dir"
    }
    trap cleanup EXIT

    mkdir -p "$temporary_dir/theme"
    printf 'background = "#101010"\nforeground = "#eeeeee"\naccent = "#112233"\n' \
        >"$temporary_dir/theme/colors.toml"
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
        OMARCHY_FACE_UNLOCK_THEME_ROOT="$temporary_dir" \
        "$app_binary" >"$temporary_dir/app.log" 2>&1 &
    app_pid=$!

    for _ in $(seq 1 40); do
        grep -Fq 'Omarchy theme loaded: #112233' "$temporary_dir/app.log" && break
        sleep 0.05
    done
    grep -Fq 'Omarchy theme loaded: #112233' "$temporary_dir/app.log"

    printf 'background = "#f0f0f0"\nforeground = "#111111"\naccent = "#aabbcc"\n' \
        >"$temporary_dir/theme/colors.toml"
    for _ in $(seq 1 40); do
        grep -Fq 'Omarchy theme loaded: #aabbcc' "$temporary_dir/app.log" && break
        sleep 0.05
    done
    grep -Fq 'Omarchy theme loaded: #aabbcc' "$temporary_dir/app.log"

    kill "$app_pid"
    wait "$app_pid" 2>/dev/null || true
    app_pid=""

    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
        "$app_binary" --camera-page-test >"$temporary_dir/camera.log" 2>&1 &
    app_pid=$!
    sleep 0.35
    if command -v fuser >/dev/null 2>&1 \
        && fuser /dev/video0 2>/dev/null | tr ' ' '\n' | grep -Fxq "$app_pid"; then
        echo "The Gaze-ready app opened /dev/video0 from its camera page." >&2
        exit 1
    fi
fi
