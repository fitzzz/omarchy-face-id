#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
main_qml="$project_dir/qml/Main.qml"

# Gaze 0.2.12 intentionally omits daemon preview frames for a shareable
# PipeWire RGB camera. Mirror its own GUI: open a parallel local preview only
# when the parsed Gaze configuration says sharing is safe.
grep -Fq 'import QtMultimedia' "$main_qml"
grep -Fq 'gazeClient.parallelPreviewAvailable' "$main_qml"
grep -Fq 'VideoOutput {' "$main_qml"
grep -Fq '&& gazeClient.parallelPreviewAvailable' "$main_qml"
grep -Fq 'interval: 1000' "$main_qml"
grep -Fq 'id: promptTransition' "$main_qml"
if grep -Fq 'Check your camera' "$main_qml"; then
    echo "The redundant camera-check step still exists." >&2
    exit 1
fi

app_binary=${OMARCHY_FACE_ID_BINARY:-"$PWD/omarchy-face-id"}
if [[ -x "$app_binary" ]]; then
    temporary_dir=$(mktemp -d -t face-id-theme-test.XXXXXX)
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
        OMARCHY_FACE_ID_THEME_ROOT="$temporary_dir" \
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
