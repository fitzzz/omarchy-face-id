#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$project_dir/scripts/install-gaze-arch.sh"
client="$project_dir/app/GazeClient.cpp"
main_qml="$project_dir/qml/Main.qml"

bash -n "$script"
grep -Fq 'omarchy pkg aur add gaze-bin' "$script"
grep -Fq 'omarchy pkg add gst-plugins-good' "$script"
grep -Fq "ownership_value='omarchy-face-id:gaze-aur:gaze-bin'" "$script"
grep -Fq "camera_support_value='omarchy-face-id:camera-support:gst-plugins-good'" "$script"
grep -Fq 'sudo systemctl enable gazed.service' "$script"
grep -Fq 'sudo systemctl restart gazed.service' "$script"
grep -Fq 'Installing Gaze…' "$script"
grep -Fq 'Installing Camera Support…' "$script"
if grep -Fq 'Installing Omarchy Face ID…' "$script"; then
    echo "The Gaze dependency installer has the wrong product heading." >&2
    exit 1
fi
grep -Fq 'QProcess::startDetached' "$client"
grep -Fq 'OMARCHY_FACE_ID_GAZE_PATH' "$client"
grep -Fq 'jpegDecoderAvailable()' "$client"
grep -Fq 'm_cameraSupportAvailable = jpegDecoderAvailable()' "$client"
grep -Fq 'gazeClient.cameraSupportAvailable' "$main_qml"
grep -Fq 'QStringLiteral(":/scripts/install-gaze-arch.sh")' "$client"
grep -Fq 'text: gazeClient.faceSetupInstalling' "$main_qml"
grep -Fq '"Install Gaze Package"' "$main_qml"
grep -Fq '? "Install Camera Support"' "$main_qml"
grep -Fq 'onClicked: gazeClient.installFaceSetup()' "$main_qml"

if rg -q 'pacman -U|curl .*gaze|packages\.gundulabs' "$script"; then
    echo "Face ID must use Omarchy's standard AUR package workflow." >&2
    exit 1
fi

temporary_dir=$(mktemp -d -t omarchy-face-id-install-test.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

run_case() {
    local mode=$1
    local sandbox="$temporary_dir/$mode"
    local status_file="/tmp/omarchy-face-id-install.$mode.$$"
    install -d "$sandbox/bin" "$sandbox/ownership"
    : >"$sandbox/actions.log"

    if [[ $mode == preexisting || $mode == complete ]]; then
        : >"$sandbox/package-present"
    fi
    if [[ $mode == complete ]]; then
        : >"$sandbox/decoder-present"
    fi

    cat >"$sandbox/bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman %s\n' "$*" >>"$TEST_LOG"
[[ $1 == -Q && $2 == gaze-bin && -f $PACKAGE_MARKER ]]
EOF
    cat >"$sandbox/bin/gst-inspect-1.0" <<'EOF'
#!/usr/bin/env bash
printf 'gst-inspect-1.0 %s\n' "$*" >>"$TEST_LOG"
[[ $1 == jpegdec && -f $DECODER_MARKER ]]
EOF
    cat >"$sandbox/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >>"$TEST_LOG"
case $* in
    'pkg aur add gaze-bin') : >"$PACKAGE_MARKER" ;;
    'pkg add gst-plugins-good') : >"$DECODER_MARKER" ;;
    *) exit 1 ;;
esac
EOF
    cat >"$sandbox/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
EOF
    cat >"$sandbox/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
case $1 in
    systemctl)
        shift
        systemctl "$@"
        ;;
    install)
        shift
        if [[ $1 == -d ]]; then
            mkdir -p -- "${@: -1}"
        else
            cp -- "${@: -2:1}" "${@: -1}"
        fi
        ;;
esac
EOF
    chmod +x "$sandbox/bin/"*

    TEST_LOG="$sandbox/actions.log" \
    PACKAGE_MARKER="$sandbox/package-present" \
    DECODER_MARKER="$sandbox/decoder-present" \
    PATH="$sandbox/bin:/usr/bin" \
    OMARCHY_FACE_ID_GAZE_COMMAND=face-id-test-gaze \
    OMARCHY_FACE_ID_OWNERSHIP_DIR="$sandbox/ownership" \
        "$script" --status-file "$status_file" >"$sandbox/output.log"

    grep -Fxq success "$status_file"
    rm -f -- "$status_file"
}

run_case fresh
grep -Fq 'omarchy pkg aur add gaze-bin' "$temporary_dir/fresh/actions.log"
grep -Fq 'omarchy pkg add gst-plugins-good' "$temporary_dir/fresh/actions.log"
grep -Fq 'sudo systemctl restart gazed.service' \
    "$temporary_dir/fresh/actions.log"
grep -Fxq 'omarchy-face-id:gaze-aur:gaze-bin' \
    "$temporary_dir/fresh/ownership/gaze-installed"
grep -Fxq 'omarchy-face-id:camera-support:gst-plugins-good' \
    "$temporary_dir/fresh/ownership/camera-support-installed"

run_case preexisting
if grep -Fq 'omarchy pkg aur add gaze-bin' \
    "$temporary_dir/preexisting/actions.log"; then
    echo "A pre-existing Gaze package would be reinstalled or claimed." >&2
    exit 1
fi
[[ ! -e $temporary_dir/preexisting/ownership/gaze-installed ]]
grep -Fq 'omarchy pkg add gst-plugins-good' \
    "$temporary_dir/preexisting/actions.log"
grep -Fxq 'omarchy-face-id:camera-support:gst-plugins-good' \
    "$temporary_dir/preexisting/ownership/camera-support-installed"

run_case complete
if grep -Eq 'omarchy pkg (add|aur add)' "$temporary_dir/complete/actions.log"; then
    echo "A complete pre-existing setup would be modified or claimed." >&2
    exit 1
fi
[[ ! -e $temporary_dir/complete/ownership/gaze-installed ]]
[[ ! -e $temporary_dir/complete/ownership/camera-support-installed ]]
