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
grep -Fq 'remove_gaze_auth_rule "$sudo_pam_file" "$sudo_pam_marker"' "$script"
grep -Fq 'remove_gaze_auth_rule "$polkit_pam_file" "$polkit_pam_marker"' "$script"
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
    install -d "$sandbox/bin" "$sandbox/ownership" "$sandbox/pam" "$sandbox/gaze"
    : >"$sandbox/actions.log"

    if [[ $mode == preexisting || $mode == complete || $mode == legacy-owned ]]; then
        : >"$sandbox/package-present"
    fi
    if [[ $mode == complete || $mode == legacy-owned ]]; then
        : >"$sandbox/decoder-present"
    fi
    if [[ $mode == preexisting || $mode == legacy-owned ]]; then
        printf '%s\n' '#%PAM-1.0' 'auth sufficient pam_gaze.so' \
            'auth include system-auth' >"$sandbox/pam/sudo"
        cp "$sandbox/pam/sudo" "$sandbox/pam/polkit-1"
        printf '%s\n' "$sandbox/pam/sudo" >"$sandbox/gaze/sudo-marker"
        printf '%s\n' "$sandbox/pam/polkit-1" >"$sandbox/gaze/polkit-marker"
    fi
    if [[ $mode == legacy-owned ]]; then
        printf '%s\n' 'omarchy-face-id:gaze:0.2.12-1' \
            >"$sandbox/ownership/gaze-installed"
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
    'pkg aur add gaze-bin')
        : >"$PACKAGE_MARKER"
        printf '%s\n' '#%PAM-1.0' 'auth sufficient pam_gaze.so' \
            'auth include system-auth' >"$SUDO_PAM_FILE"
        cp "$SUDO_PAM_FILE" "$POLKIT_PAM_FILE"
        printf '%s\n' "$SUDO_PAM_FILE" >"$SUDO_PAM_MARKER"
        printf '%s\n' "$POLKIT_PAM_FILE" >"$POLKIT_PAM_MARKER"
        ;;
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
    OMARCHY_FACE_ID_SUDO_PAM_PATH="$sandbox/pam/sudo" \
    OMARCHY_FACE_ID_POLKIT_PAM_PATH="$sandbox/pam/polkit-1" \
    OMARCHY_FACE_ID_GAZE_SUDO_MARKER="$sandbox/gaze/sudo-marker" \
    OMARCHY_FACE_ID_GAZE_POLKIT_MARKER="$sandbox/gaze/polkit-marker" \
    SUDO_PAM_FILE="$sandbox/pam/sudo" \
    POLKIT_PAM_FILE="$sandbox/pam/polkit-1" \
    SUDO_PAM_MARKER="$sandbox/gaze/sudo-marker" \
    POLKIT_PAM_MARKER="$sandbox/gaze/polkit-marker" \
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
! grep -Fq pam_gaze.so "$temporary_dir/fresh/pam/sudo"
! grep -Fq pam_gaze.so "$temporary_dir/fresh/pam/polkit-1"

run_case preexisting
if grep -Fq 'omarchy pkg aur add gaze-bin' \
    "$temporary_dir/preexisting/actions.log"; then
    echo "A pre-existing Gaze package would be reinstalled or claimed." >&2
    exit 1
fi
[[ ! -e $temporary_dir/preexisting/ownership/gaze-installed ]]
grep -Fq pam_gaze.so "$temporary_dir/preexisting/pam/sudo"
grep -Fq pam_gaze.so "$temporary_dir/preexisting/pam/polkit-1"
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

run_case legacy-owned
! grep -Fq pam_gaze.so "$temporary_dir/legacy-owned/pam/sudo"
! grep -Fq pam_gaze.so "$temporary_dir/legacy-owned/pam/polkit-1"
