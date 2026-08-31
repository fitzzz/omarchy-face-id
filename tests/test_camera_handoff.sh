#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
main_qml="$project_dir/qml/Main.qml"

# Gaze 0.2.12 intentionally omits daemon preview frames for a shareable
# PipeWire RGB camera. Use a second PipeWire stream, never Qt Multimedia's
# exclusive FFmpeg/V4L2 camera path, for the local preview.
grep -Fq 'pipewiresrc do-timestamp=true' "$project_dir/app/GazeClient.cpp"
grep -Fq 'video/x-raw,pixel-aspect-ratio=1/1; image/jpeg' \
    "$project_dir/app/GazeClient.cpp"
grep -Fq 'decodebin' "$project_dir/app/GazeClient.cpp"
grep -Fq 'startParallelPreview()' "$project_dir/app/GazeClient.cpp"
grep -Fq 'QTimer::singleShot(1000, this, [this, enrollmentGeneration]' \
    "$project_dir/app/GazeClient.cpp"
enroll_start_line=$(grep -nF 'iface.asyncCall(QStringLiteral("EnrollStart")' \
    "$project_dir/app/GazeClient.cpp" | cut -d: -f1)
preview_delay_line=$(grep -nF 'QTimer::singleShot(1000, this, [this, enrollmentGeneration]' \
    "$project_dir/app/GazeClient.cpp" | cut -d: -f1)
if ((preview_delay_line <= enroll_start_line)); then
    echo "The optional preview can still take the camera before Gaze enrollment." >&2
    exit 1
fi
grep -Fq 'gazeClient.previewDataUrl.length > 0' "$main_qml"
grep -Fq 'retainWhileLoading: true' "$main_qml"
grep -Fq "now - last < 80'000" "$project_dir/app/GazeClient.cpp"
if grep -Eq 'QtMultimedia|VideoOutput \{|Camera \{' "$main_qml"; then
    echo "The exclusive Qt Multimedia camera path is still present." >&2
    exit 1
fi
grep -Fq 'id: promptTransition' "$main_qml"
if grep -Fq 'id: promptDelay' "$main_qml"; then
    echo "Enrollment instructions still lag behind Gaze's active pose." >&2
    exit 1
fi
grep -Fq 'root.displayedPrompt = "Scan complete."' "$main_qml"
grep -Fq 'id: prepareLayout' "$main_qml"
grep -Fq 'id: prepareTitleGap' "$main_qml"
grep -Fq 'border.color: root.accentColor' "$main_qml"
if grep -Fq ': root.gazeReady ? root.accentColor : root.errorColor' "$main_qml"; then
    echo "The Prepare panel still uses an error border when Gaze is missing." >&2
    exit 1
fi
grep -Fq 'id: scanLayout' "$main_qml"
grep -Fq 'checkingColor: root.accentColor' "$main_qml"
grep -Fq '"captured": "Perfect."' "$main_qml"
grep -Fq 'playDing();' "$project_dir/app/GazeClient.cpp"
grep -Fq 'assets/ding.mp3' "$project_dir/CMakeLists.txt"
grep -Fq 'QDBusPendingCallWatcher' "$project_dir/app/GazeClient.cpp"
grep -Fq 'iface.setTimeout(120000)' "$project_dir/app/GazeClient.cpp"
grep -Fq 'iface.asyncCall(QStringLiteral("EnrollStart")' \
    "$project_dir/app/GazeClient.cpp"
if grep -Fq 'iface.call(QStringLiteral("EnrollStart")' \
    "$project_dir/app/GazeClient.cpp"; then
    echo "Enrollment authorization still blocks the Qt UI thread." >&2
    exit 1
fi
if grep -Fq 'gazeClient.enrolling ? root.amberColor' "$main_qml"; then
    echo "The enrollment ring is still pinned to the warning color." >&2
    exit 1
fi
[[ $(grep -Fc 'spacing: root.scanPageSpacing' "$main_qml") -eq 2 ]]
[[ $(grep -Fc 'Layout.minimumHeight: root.scanPanelMinimumHeight' "$main_qml") -eq 2 ]]
if grep -Fq 'Check your camera' "$main_qml"; then
    echo "The redundant camera-check step still exists." >&2
    exit 1
fi
if grep -Fq 'M9 9.5c.2 1.3.8 2 1.8 2H12' \
    "$project_dir/qml/components/FaceScanIndicator.qml"; then
    echo "The moving enrollment avatar still includes a nose path."
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
