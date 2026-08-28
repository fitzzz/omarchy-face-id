#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
main_qml="$project_dir/qml/Main.qml"

# Gaze is the only camera owner. The setup app consumes Gaze's preview frames
# and must never construct a second Qt Multimedia camera pipeline.
if grep -Eq 'QtMultimedia|VideoOutput|(^|[[:space:]])Camera[[:space:]]*\{' "$main_qml"; then
    echo "The setup app contains a competing Qt camera pipeline." >&2
    exit 1
fi
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
