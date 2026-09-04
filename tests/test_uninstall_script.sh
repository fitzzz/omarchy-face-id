#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$project_root/scripts/uninstall.sh"
bash -n "$script"
grep -Fq 'gaze remove-face "$face_name" --user "$account_name"' "$script"
grep -Fq 'last_registered_user' "$script"
grep -Fq 'OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH' "$script"
grep -Fq 'OMARCHY_FACE_ID_VERIFY_PAM_DIR' "$script"
grep -Fq 'root_remove' "$script"
grep -Fq 'if ((status != 0 && transaction_active)); then rollback; fi' "$script"
! rg -q 'rm -rf -- /etc/gaze|rm -rf -- /var/(cache|lib)/gaze|gaze clear-user' "$script"

temporary_dir=$(mktemp -d -t omarchy-face-id-uninstall-test.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

make_sandbox() {
    local sandbox=$1 mode=$2
    install -d "$sandbox/bin" "$sandbox/plugin" "$sandbox/state/omarchy-face-id" "$sandbox/ownership/users" \
        "$sandbox/pam.d" "$sandbox/libexec" "$sandbox/security" "$sandbox/shared-biometric" "$sandbox/verify-pam"
    : >"$sandbox/actions.log"; : >"$sandbox/sudo-count"
    printf '%s\n' '{"id": "fitzzz.face-id"}' >"$sandbox/plugin/manifest.json"
    printf '%s\n' '# Face-only service for Omarchy Face ID.' >"$sandbox/pam.d/omarchy-face-id-lock"
    printf '%s\n' default >"$sandbox/state/omarchy-face-id/enrolled-face"
    printf '%s\n' '#%PAM-1.0' '# BEGIN Omarchy Face ID sudo' \
        'auth include omarchy-face-id' '# END Omarchy Face ID sudo' \
        'auth include system-auth' >"$sandbox/pam.d/sudo"
    printf '%s\n' '# Omarchy Face ID sudo authentication. Managed by Omarchy Face ID.' \
        'auth [success=done auth_err=die default=ignore] pam_omarchy_face_id_consent.so helper=/test' >"$sandbox/pam.d/omarchy-face-id"
    printf '%s\n' '# Omarchy Face ID private face verification. Managed by Omarchy Face ID.' \
        'auth [success=done ignore=ignore default=bad] pam_gaze.so' \
        'auth required pam_deny.so' 'account required pam_permit.so' >"$sandbox/verify-pam/sudo"
    printf '%s\n' '#!/usr/bin/env bash' '[[ ${1:-} == --version ]] && echo "Omarchy Face ID elevation bridge 1"' >"$sandbox/libexec/elevation"
    chmod +x "$sandbox/libexec/elevation"
    printf '%s\n' 'Omarchy Face ID consent module 1' >"$sandbox/security/consent.so"
    printf '%s\n' 'must survive' >"$sandbox/shared-biometric/another-user.face"

    case $mode in
        last-owned)
            printf '%s\n' 'omarchy-face-id:registered-user:1' >"$sandbox/ownership/users/$(id -u)"
            printf '%s\n' 'omarchy-face-id:gaze-aur:gaze-bin' >"$sandbox/ownership/gaze-installed"
            printf '%s\n' 'omarchy-face-id:camera-support:gst-plugins-good' >"$sandbox/ownership/camera-support-installed" ;;
        multi-user)
            printf '%s\n' 'omarchy-face-id:registered-user:1' >"$sandbox/ownership/users/$(id -u)"
            printf '%s\n' 'omarchy-face-id:registered-user:1' >"$sandbox/ownership/users/424242"
            printf '%s\n' 'omarchy-face-id:gaze-aur:gaze-bin' >"$sandbox/ownership/gaze-installed" ;;
        preexisting)
            printf '%s\n' 'omarchy-face-id:registered-user:1' >"$sandbox/ownership/users/$(id -u)" ;;
        legacy) : ;;
    esac
    printf '%s\n' 'omarchy-face-id:sudo:added' >"$sandbox/ownership/sudo-integration"

    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "gaze %s\n" "$*" >>"$TEST_LOG"' \
        'if [[ $1 == list-faces ]]; then printf "  • default [RGB] (5 captures)\n"; fi' >"$sandbox/bin/gaze"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "omarchy %s\n" "$*" >>"$TEST_LOG"' \
        'if [[ $1 == plugin && $2 == remove ]]; then rm -rf -- "$PLUGIN_TARGET"; fi' >"$sandbox/bin/omarchy"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "pacman %s\n" "$*" >>"$TEST_LOG"' \
        '[[ $1 == -Q && ( $2 == gaze-bin || $2 == gst-plugins-good ) ]]' >"$sandbox/bin/pacman"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "systemctl %s\n" "$*" >>"$TEST_LOG"' >"$sandbox/bin/systemctl"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "sudo %s\n" "$*" >>"$TEST_LOG"' \
        'count=$(cat "$SUDO_COUNT"); count=$((count+1)); printf "%s\n" "$count" >"$SUDO_COUNT"' \
        'if [[ ${FAIL_AT:-0} -eq $count && ! -e $FAIL_ONCE ]]; then : >"$FAIL_ONCE"; exit 97; fi' \
        'cmd=$1; shift' \
        'case $cmd in' \
        ' install) if [[ " $* " == *" -d "* ]]; then mkdir -p -- "${@: -1}"; else mkdir -p -- "$(dirname -- "${@: -1}")"; cp -- "${@: -2:1}" "${@: -1}"; fi ;;' \
        ' cp) [[ ${1:-} == -a ]] && shift; [[ ${1:-} == -- ]] && shift; cp -a -- "$1" "$2" ;;' \
        ' mv) [[ ${1:-} == -f ]] && shift; [[ ${1:-} == -- ]] && shift; mv -f -- "$1" "$2" ;;' \
        ' rm) command rm "$@" ;;' \
        ' unlink) unlink "$1" ;;' \
        ' rmdir) rmdir "$@" ;;' \
        ' systemctl) systemctl "$@" ;;' \
        ' pacman) pacman "$@" ;;' \
        ' *) if [[ $cmd == */uninstall.sh ]]; then "$cmd" "$@"; else exit 98; fi ;;' \
        'esac' >"$sandbox/bin/sudo"
    chmod +x "$sandbox/bin/"*
}

run_uninstall() {
    local sandbox=$1 fail_at=${2:-0} fail_root_at=${3:-0}
    set +e
    TEST_LOG="$sandbox/actions.log" SUDO_COUNT="$sandbox/sudo-count" FAIL_AT="$fail_at" FAIL_ONCE="$sandbox/failed-once" \
    PLUGIN_TARGET="$sandbox/plugin" PATH="$sandbox/bin:/usr/bin" OMARCHY_FACE_ID_TEST_ROOT="$sandbox" \
    XDG_STATE_HOME="$sandbox/state" OMARCHY_FACE_ID_PLUGIN_TARGET="$sandbox/plugin" \
    OMARCHY_FACE_ID_PAM_PATH="$sandbox/pam.d/omarchy-face-id-lock" OMARCHY_FACE_ID_OWNERSHIP_DIR="$sandbox/ownership" \
    OMARCHY_FACE_ID_SUDO_PAM_PATH="$sandbox/pam.d/sudo" OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH="$sandbox/pam.d/omarchy-face-id" \
    OMARCHY_FACE_ID_ELEVATION_TARGET="$sandbox/libexec/elevation" OMARCHY_FACE_ID_CONSENT_TARGET="$sandbox/security/consent.so" \
    OMARCHY_FACE_ID_VERIFY_PAM_DIR="$sandbox/verify-pam" \
    OMARCHY_FACE_ID_FAIL_ROOT_STEP="$fail_root_at" OMARCHY_FACE_ID_SKIP_LOCK_CHECK=1 \
        "$script" --yes >"$sandbox/output.log" 2>&1
    RUN_STATUS=$?
    set -e
}

# Another registered user keeps every shared system component and package.
multi="$temporary_dir/multi"; make_sandbox "$multi" multi-user; run_uninstall "$multi"
if [[ $RUN_STATUS -ne 0 ]]; then cat "$multi/output.log" >&2; exit 1; fi
[[ -e $multi/ownership/users/424242 && ! -e $multi/ownership/users/$(id -u) ]]
[[ -e $multi/pam.d/omarchy-face-id && -e $multi/libexec/elevation && -e $multi/security/consent.so ]]
[[ -e $multi/verify-pam/sudo ]]
[[ -e $multi/pam.d/omarchy-face-id-lock ]]
grep -Fqx 'auth include omarchy-face-id' "$multi/pam.d/sudo"
! grep -Eq 'omarchy pkg drop|gaze uninstall|sudo pacman' "$multi/actions.log"
grep -Fxq 'must survive' "$multi/shared-biometric/another-user.face"

# The proven final user removes owned packages and the dedicated PAM include,
# but never recursively deletes biometric storage.
last="$temporary_dir/last"; make_sandbox "$last" last-owned; run_uninstall "$last"
if [[ $RUN_STATUS -ne 0 ]]; then cat "$last/output.log" >&2; exit 1; fi
grep -Fq 'gaze remove-face default --user' "$last/actions.log"
grep -Fq 'gaze uninstall --yes' "$last/actions.log"
grep -Fq 'omarchy pkg drop gst-plugins-good' "$last/actions.log"
! grep -Fq 'BEGIN Omarchy Face ID sudo' "$last/pam.d/sudo"
grep -Fqx 'auth include system-auth' "$last/pam.d/sudo"
[[ ! -e $last/pam.d/omarchy-face-id && ! -e $last/libexec/elevation && ! -e $last/security/consent.so ]]
[[ ! -e $last/verify-pam/sudo ]]
[[ ! -e $last/pam.d/omarchy-face-id-lock ]]
grep -Fxq 'must survive' "$last/shared-biometric/another-user.face"

# Pre-existing packages have no ownership receipt and are never removed.
pre="$temporary_dir/pre"; make_sandbox "$pre" preexisting; run_uninstall "$pre"; [[ $RUN_STATUS -eq 0 ]]
! grep -Eq 'omarchy pkg drop|gaze uninstall|sudo pacman' "$pre/actions.log"

# A legacy install without the root-owned registry is not proof that this is
# the final user, so all shared components are retained.
legacy="$temporary_dir/legacy"; make_sandbox "$legacy" legacy; run_uninstall "$legacy"; [[ $RUN_STATUS -eq 0 ]]
grep -Fq 'Shared components were kept' "$legacy/output.log"
[[ -e $legacy/pam.d/omarchy-face-id && -e $legacy/ownership/gaze-installed || ! -e $legacy/ownership/gaze-installed ]]

# Inject every failure inside the root-owned transaction. Every checkpoint
# must restore the exact original sudo stack and shared lock PAM service.
baseline="$temporary_dir/baseline"; make_sandbox "$baseline" last-owned; run_uninstall "$baseline"
root_steps=$(cat "$baseline/uninstall-root-step-count")
for ((step=1; step<=root_steps; step++)); do
    sandbox="$temporary_dir/failure-$step"; make_sandbox "$sandbox" last-owned
    original=$(sha256sum "$sandbox/pam.d/sudo" | cut -d' ' -f1)
    run_uninstall "$sandbox" 0 "$step"
    [[ $RUN_STATUS -ne 0 ]]
    [[ $(sha256sum "$sandbox/pam.d/sudo" | cut -d' ' -f1) == "$original" ]]
    grep -Fqx 'auth include system-auth' "$sandbox/pam.d/sudo"
    [[ -e $sandbox/pam.d/omarchy-face-id-lock ]]
done

# Failure to enter the root transaction changes no system authentication file.
outer="$temporary_dir/outer-failure"; make_sandbox "$outer" last-owned
outer_original=$(sha256sum "$outer/pam.d/sudo" | cut -d' ' -f1)
run_uninstall "$outer" 1
[[ $RUN_STATUS -ne 0 ]]
[[ $(sha256sum "$outer/pam.d/sudo" | cut -d' ' -f1) == "$outer_original" ]]

# A sandboxed test cannot accidentally target live PAM.
guard="$temporary_dir/guard"; make_sandbox "$guard" preexisting
set +e
TEST_LOG="$guard/actions.log" SUDO_COUNT="$guard/sudo-count" FAIL_AT=0 FAIL_ONCE="$guard/failed-once" PLUGIN_TARGET="$guard/plugin" \
PATH="$guard/bin:/usr/bin" OMARCHY_FACE_ID_TEST_ROOT="$guard" XDG_STATE_HOME="$guard/state" OMARCHY_FACE_ID_PLUGIN_TARGET="$guard/plugin" \
OMARCHY_FACE_ID_PAM_PATH="$guard/pam.d/omarchy-face-id-lock" OMARCHY_FACE_ID_OWNERSHIP_DIR="$guard/ownership" \
OMARCHY_FACE_ID_SUDO_PAM_PATH=/etc/pam.d/sudo OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH="$guard/pam.d/omarchy-face-id" \
OMARCHY_FACE_ID_VERIFY_PAM_DIR="$guard/verify-pam" \
OMARCHY_FACE_ID_ELEVATION_TARGET="$guard/libexec/elevation" OMARCHY_FACE_ID_CONSENT_TARGET="$guard/security/consent.so" \
OMARCHY_FACE_ID_SKIP_LOCK_CHECK=1 "$script" --yes >/dev/null 2>&1
guard_status=$?
set -e
[[ $guard_status -ne 0 && ! -s $guard/actions.log ]]
