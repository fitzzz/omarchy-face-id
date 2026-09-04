#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$project_dir/scripts/install-gaze-arch.sh"
bash -n "$script"
grep -Fq "hook_line='auth include omarchy-face-id'" "$script"
grep -Fq 'OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH' "$script"
grep -Fq 'OMARCHY_FACE_ID_VERIFY_PAM_DIR' "$script"
grep -Fq 'camera_preexisting' "$script"
grep -Fq 'user_registry_dir=' "$script"
grep -Fq '/proc/$$/fd/' "$script"
grep -Fq 'rollback()' "$script"
grep -Fq 'flock -x' "$script"
! grep -Fq 'sleep 1' "$script"
if rg -q 'pacman -U|curl .*gaze|packages\.gundulabs' "$script"; then
    echo "Face ID must use Omarchy's package workflows." >&2; exit 1
fi
verifier_install_line=$(grep -n -m1 'atomic_copy "$verifier_temp"' "$script" | cut -d: -f1)
sudo_hook_line=$(grep -n -m1 'atomic_copy "$sudo_temp"' "$script" | cut -d: -f1)
[[ -n $verifier_install_line && -n $sudo_hook_line \
    && $verifier_install_line -lt $sudo_hook_line ]] || {
    echo 'The private verifier must be installed before the sudo hook is exposed.' >&2
    exit 1
}

temporary_dir=$(mktemp -d -t omarchy-face-id-install-test.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

make_sandbox() {
    local sandbox=$1 mode=${2:-fresh}
    install -d "$sandbox/bin" "$sandbox/ownership" "$sandbox/pam" "$sandbox/gaze" "$sandbox/payload" "$sandbox/verify-pam"
    : >"$sandbox/actions.log"; : >"$sandbox/sudo-count"
    printf '%s\n' '#%PAM-1.0' 'auth include system-auth' >"$sandbox/pam/sudo"
    printf '%s\n' '#!/usr/bin/env bash' '# Omarchy Face ID elevation bridge 1' 'exit 0' >"$sandbox/payload/elevation"; chmod +x "$sandbox/payload/elevation"
    printf '%s\n' 'Omarchy Face ID consent module 1' >"$sandbox/payload/consent.so"
    if [[ $mode == preexisting-camera || $mode == complete ]]; then : >"$sandbox/camera-package"; fi
    if [[ $mode == complete ]]; then : >"$sandbox/decoder"; : >"$sandbox/gaze-package"; fi
    if [[ $mode == preexisting-camera ]]; then : >"$sandbox/gaze-package"; fi

    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "pacman %s\n" "$*" >>"$TEST_LOG"' \
        '[[ $1 == -Q && $2 == gaze-bin && -f $GAZE_PACKAGE ]] && exit 0' \
        '[[ $1 == -Q && $2 == gst-plugins-good && -f $CAMERA_PACKAGE ]] && exit 0' \
        'exit 1' >"$sandbox/bin/pacman"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "gst-inspect-1.0 %s\n" "$*" >>"$TEST_LOG"' \
        '[[ $1 == jpegdec && -f $DECODER ]]' >"$sandbox/bin/gst-inspect-1.0"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "omarchy %s\n" "$*" >>"$TEST_LOG"' \
        'case $* in' \
        '  "pkg add gst-plugins-good") : >"$CAMERA_PACKAGE"; : >"$DECODER" ;;' \
        '  "pkg aur add gaze-bin") : >"$GAZE_PACKAGE" ;;' \
        '  "pkg drop gst-plugins-good") rm -f -- "$CAMERA_PACKAGE" "$DECODER" ;;' \
        '  "pkg drop gaze-bin") rm -f -- "$GAZE_PACKAGE" ;;' \
        '  *) exit 1 ;;' \
        'esac' >"$sandbox/bin/omarchy"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "systemctl %s\n" "$*" >>"$TEST_LOG"' >"$sandbox/bin/systemctl"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "sudo %s\n" "$*" >>"$TEST_LOG"' \
        'count=$(cat "$SUDO_COUNT"); count=$((count+1)); printf "%s\n" "$count" >"$SUDO_COUNT"' \
        'if [[ ${FAIL_AT:-0} -eq $count && ! -e $FAIL_ONCE ]]; then : >"$FAIL_ONCE"; exit 97; fi' \
        'cmd=$1; shift' \
        'if [[ $cmd == "$INSTALL_SCRIPT" ]]; then echo "root cannot reopen the AppImage FUSE path" >&2; exit 126; fi' \
        'case $cmd in' \
        ' /usr/bin/bash) [[ ${1:-} == -s ]] || exit 98; shift; /usr/bin/bash -s "$@" ;;' \
        ' systemctl) systemctl "$@" ;;' \
        ' install)' \
        '   if [[ " $* " == *" -d "* ]]; then mkdir -p -- "${@: -1}"' \
        '   else mkdir -p -- "$(dirname -- "${@: -1}")"; cp -- "${@: -2:1}" "${@: -1}"; [[ " $* " == *" -m 0755 "* ]] && chmod 0755 "${@: -1}" || true; fi ;;' \
        ' cp) [[ ${1:-} == -a ]] && shift; [[ ${1:-} == -- ]] && shift; cp -a -- "$1" "$2" ;;' \
        ' mv) [[ ${1:-} == -f ]] && shift; [[ ${1:-} == -- ]] && shift; mv -f -- "$1" "$2" ;;' \
        ' rm) command rm "$@" ;;' \
        ' unlink) unlink "$1" ;;' \
        ' rmdir) rmdir "$@" ;;' \
        ' *) exit 98 ;;' \
        'esac' >"$sandbox/bin/sudo"
    chmod +x "$sandbox/bin/"*
}

run_install() {
    local sandbox=$1 fail_at=${2:-0} root_fail_at=${3:-0} status="/tmp/omarchy-face-id-install.$$.${RANDOM}"
    local elevation_sha consent_sha
    elevation_sha=$(sha256sum "$sandbox/payload/elevation" | cut -d' ' -f1)
    consent_sha=$(sha256sum "$sandbox/payload/consent.so" | cut -d' ' -f1)
    set +e
    TEST_LOG="$sandbox/actions.log" SUDO_COUNT="$sandbox/sudo-count" FAIL_AT="$fail_at" FAIL_ONCE="$sandbox/failed-once" \
    INSTALL_SCRIPT="$script" OMARCHY_FACE_ID_FAIL_ROOT_STEP="$root_fail_at" \
    GAZE_PACKAGE="$sandbox/gaze-package" CAMERA_PACKAGE="$sandbox/camera-package" DECODER="$sandbox/decoder" \
    PATH="$sandbox/bin:/usr/bin" OMARCHY_FACE_ID_TEST_ROOT="$sandbox" \
    OMARCHY_FACE_ID_GAZE_COMMAND=face-id-test-gaze OMARCHY_FACE_ID_OWNERSHIP_DIR="$sandbox/ownership" \
    OMARCHY_FACE_ID_SUDO_PAM_PATH="$sandbox/pam/sudo" OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH="$sandbox/pam/omarchy-face-id" \
    OMARCHY_FACE_ID_POLKIT_PAM_PATH="$sandbox/pam/polkit-1" OMARCHY_FACE_ID_GAZE_POLKIT_MARKER="$sandbox/gaze/polkit-marker" \
    OMARCHY_FACE_ID_ELEVATION_TARGET="$sandbox/libexec/elevation" OMARCHY_FACE_ID_CONSENT_TARGET="$sandbox/security/consent.so" \
    OMARCHY_FACE_ID_VERIFY_PAM_DIR="$sandbox/verify-pam" \
        "$script" --elevation-helper "$sandbox/payload/elevation" --elevation-sha256 "$elevation_sha" \
        --consent-module "$sandbox/payload/consent.so" --consent-sha256 "$consent_sha" --status-file "$status" \
        >"$sandbox/output.log" 2>&1
    RUN_STATUS=$?
    set -e
    rm -f -- "$status"
}

fresh="$temporary_dir/fresh"; make_sandbox "$fresh"; run_install "$fresh"
if [[ $RUN_STATUS -ne 0 ]]; then cat "$fresh/output.log" >&2; exit 1; fi
if find "$fresh" -maxdepth 1 -type d -name 'root-stream.*' -print -quit | grep -q .; then
    echo 'The private root handoff was not removed.' >&2
    exit 1
fi
grep -Fqx '# BEGIN Omarchy Face ID sudo' "$fresh/pam/sudo"
grep -Fqx 'auth include omarchy-face-id' "$fresh/pam/sudo"
cat >"$fresh/expected-face-pam" <<EOF
# Omarchy Face ID sudo authentication. Managed by Omarchy Face ID.
auth [success=done auth_err=die default=ignore] pam_omarchy_face_id_consent.so helper=$fresh/libexec/elevation
EOF
cmp "$fresh/expected-face-pam" "$fresh/pam/omarchy-face-id"
cat >"$fresh/expected-verifier-pam" <<'EOF'
# Omarchy Face ID private face verification. Managed by Omarchy Face ID.
auth [success=done ignore=ignore default=bad] pam_gaze.so
auth required pam_deny.so
account required pam_permit.so
EOF
cmp "$fresh/expected-verifier-pam" "$fresh/verify-pam/sudo"
! grep -Eq 'pam_exec\.so| rejected$| unlocked$' "$fresh/pam/omarchy-face-id"
grep -Fxq 'omarchy-face-id:registered-user:1' "$fresh/ownership/users/$(id -u)"
grep -Fxq 'omarchy-face-id:camera-support:gst-plugins-good' "$fresh/ownership/camera-support-installed"
grep -Fxq 'omarchy-face-id:gaze-aur:gaze-bin' "$fresh/ownership/gaze-installed"
cmp "$fresh/payload/elevation" "$fresh/libexec/elevation"
cmp "$fresh/payload/consent.so" "$fresh/security/consent.so"
[[ $(grep -Fxc 'sudo /usr/bin/bash -s' "$fresh/actions.log") -eq 1 ]]
! grep -Eq '^sudo .*/install-gaze-arch\.sh ' "$fresh/actions.log"
fresh_sudo_steps=$(cat "$fresh/sudo-count")
root_steps=$(cat "$fresh/root-step-count")

# A rerun converges to one hook and does not reinstall packages.
: >"$fresh/actions.log"; : >"$fresh/sudo-count"; rm -f "$fresh/failed-once"
run_install "$fresh"; [[ $RUN_STATUS -eq 0 ]]
[[ $(grep -Fxc '# BEGIN Omarchy Face ID sudo' "$fresh/pam/sudo") -eq 1 ]]
! grep -Eq 'omarchy pkg (add|aur add)' "$fresh/actions.log"

# An upgrade replaces already-managed executable and PAM payload bytes while
# preserving the stable sudo hook and dependency ownership. Versions installed
# before 0.7.60 exposed only their version string, not the permanent marker.
printf '%s\n' '#!/usr/bin/env bash' \
    '[[ ${1:-} == --version ]] && echo "Omarchy Face ID elevation helper 2"' \
    >"$fresh/libexec/elevation"
chmod +x "$fresh/libexec/elevation"
printf '%s\n' 'Omarchy Face ID consent module 1' 'candidate-two' \
    >"$fresh/payload/consent.so"
: >"$fresh/actions.log"; : >"$fresh/sudo-count"; rm -f "$fresh/failed-once"
run_install "$fresh"; [[ $RUN_STATUS -eq 0 ]]
cmp "$fresh/payload/consent.so" "$fresh/security/consent.so"
cmp "$fresh/payload/elevation" "$fresh/libexec/elevation"
[[ $(grep -Fxc '# BEGIN Omarchy Face ID sudo' "$fresh/pam/sudo") -eq 1 ]]
! grep -Eq 'omarchy pkg (add|aur add)' "$fresh/actions.log"

# An installed-but-broken camera package is repaired but never claimed.
camera="$temporary_dir/preexisting-camera"; make_sandbox "$camera" preexisting-camera; run_install "$camera"; [[ $RUN_STATUS -eq 0 ]]
grep -Fq 'omarchy pkg add gst-plugins-good' "$camera/actions.log"
[[ ! -e $camera/ownership/camera-support-installed ]]

# Every privileged failure is injected only through fake commands and must
# preserve the exact original sudo stack, including password authentication.
sudo_steps=$fresh_sudo_steps
for ((step=1; step<=sudo_steps; step++)); do
    sandbox="$temporary_dir/failure-$step"; make_sandbox "$sandbox"
    original=$(sha256sum "$sandbox/pam/sudo" | cut -d' ' -f1)
    run_install "$sandbox" "$step"
    [[ $RUN_STATUS -ne 0 ]]
    [[ $(sha256sum "$sandbox/pam/sudo" | cut -d' ' -f1) == "$original" ]]
    grep -Fqx 'auth include system-auth' "$sandbox/pam/sudo"
    : >"$sandbox/sudo-count"; rm -f "$sandbox/failed-once"
    run_install "$sandbox"; [[ $RUN_STATUS -eq 0 ]]
done

# Inject every mutation checkpoint inside the single fake-root transaction.
for ((step=1; step<=root_steps; step++)); do
    sandbox="$temporary_dir/root-failure-$step"; make_sandbox "$sandbox"
    original=$(sha256sum "$sandbox/pam/sudo" | cut -d' ' -f1)
    run_install "$sandbox" 0 "$step"
    [[ $RUN_STATUS -ne 0 ]]
    [[ $(sha256sum "$sandbox/pam/sudo" | cut -d' ' -f1) == "$original" ]]
    grep -Fqx 'auth include system-auth' "$sandbox/pam/sudo"
    : >"$sandbox/sudo-count"; rm -f "$sandbox/failed-once"
    run_install "$sandbox"; [[ $RUN_STATUS -eq 0 ]]
    [[ $(grep -Fxc '# BEGIN Omarchy Face ID sudo' "$sandbox/pam/sudo") -eq 1 ]]
done

# The hard guard must reject a sandbox run that points any target at live /etc.
guard="$temporary_dir/guard"; make_sandbox "$guard"
set +e
TEST_LOG="$guard/actions.log" SUDO_COUNT="$guard/sudo-count" FAIL_AT=0 FAIL_ONCE="$guard/failed-once" \
GAZE_PACKAGE="$guard/gaze-package" CAMERA_PACKAGE="$guard/camera-package" DECODER="$guard/decoder" PATH="$guard/bin:/usr/bin" \
OMARCHY_FACE_ID_TEST_ROOT="$guard" OMARCHY_FACE_ID_OWNERSHIP_DIR="$guard/ownership" OMARCHY_FACE_ID_SUDO_PAM_PATH=/etc/pam.d/sudo \
OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH="$guard/pam/omarchy-face-id" OMARCHY_FACE_ID_POLKIT_PAM_PATH="$guard/pam/polkit-1" \
OMARCHY_FACE_ID_VERIFY_PAM_DIR="$guard/verify-pam" \
OMARCHY_FACE_ID_GAZE_POLKIT_MARKER="$guard/gaze/polkit-marker" OMARCHY_FACE_ID_ELEVATION_TARGET="$guard/libexec/elevation" \
OMARCHY_FACE_ID_CONSENT_TARGET="$guard/security/consent.so" "$script" --elevation-helper "$guard/payload/elevation" \
--consent-module "$guard/payload/consent.so" >/dev/null 2>&1
guard_status=$?
set -e
[[ $guard_status -ne 0 ]]
[[ ! -s $guard/actions.log ]]
