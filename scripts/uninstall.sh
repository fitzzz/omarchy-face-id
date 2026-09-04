#!/usr/bin/env bash
set -euo pipefail

plugin_id=fitzzz.face-id
plugin_target="${OMARCHY_FACE_ID_PLUGIN_TARGET:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$plugin_id}"
pam_target="${OMARCHY_FACE_ID_PAM_PATH:-/etc/pam.d/omarchy-face-id-lock}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-face-id"
face_receipt="$state_dir/enrolled-face"
ownership_dir="${OMARCHY_FACE_ID_OWNERSHIP_DIR:-/var/lib/omarchy-face-id}"
gaze_receipt="$ownership_dir/gaze-installed"
camera_support_receipt="$ownership_dir/camera-support-installed"
sudo_integration_receipt="$ownership_dir/sudo-integration"
user_registry_dir="$ownership_dir/users"
user_registry_value='omarchy-face-id:registered-user:1'
sudo_pam_file="${OMARCHY_FACE_ID_SUDO_PAM_PATH:-/etc/pam.d/sudo}"
face_id_pam_file="${OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH:-${sudo_pam_file%/*}/omarchy-face-id}"
elevation_target="${OMARCHY_FACE_ID_ELEVATION_TARGET:-/usr/libexec/omarchy-face-id-elevation}"
consent_target="${OMARCHY_FACE_ID_CONSENT_TARGET:-/usr/lib/security/pam_omarchy_face_id_consent.so}"
verifier_pam_dir="${OMARCHY_FACE_ID_VERIFY_PAM_DIR:-/usr/lib/omarchy-face-id/pam.d}"
verifier_pam_file="$verifier_pam_dir/sudo"
expected_gaze_receipt='omarchy-face-id:gaze:0.2.12-1'
expected_gaze_aur_receipt='omarchy-face-id:gaze-aur:gaze-bin'
expected_camera_support_receipt='omarchy-face-id:camera-support:gst-plugins-good'
expected_sudo_added='omarchy-face-id:sudo:added'
expected_sudo_replaced='omarchy-face-id:sudo:restore-gaze'
test_root="${OMARCHY_FACE_ID_TEST_ROOT:-}"
assume_yes=0
root_mode=0
root_user_id=''
root_last_user=''
root_sudo_integration=''
root_gaze_owned=''
root_camera_owned=''

guard_test_environment() {
    [[ -z $test_root ]] && return 0
    [[ $test_root == /tmp/* && -d $test_root ]] || { echo 'Unsafe Face ID test root.' >&2; exit 2; }
    local path command_name command_path
    for path in "$plugin_target" "$pam_target" "$state_dir" "$ownership_dir" "$sudo_pam_file" "$face_id_pam_file" "$elevation_target" "$consent_target" "$verifier_pam_dir" "$verifier_pam_file"; do
        [[ $path == "$test_root"/* ]] || { echo "Refusing live system path during a sandboxed test: $path" >&2; exit 2; }
    done
    for command_name in sudo pacman omarchy; do
        command_path=$(command -v "$command_name" 2>/dev/null || true)
        [[ $command_path == "$test_root"/bin/* ]] || { echo "Refusing live command during a sandboxed test: $command_name" >&2; exit 2; }
    done
}

root_remove() {
    guard_test_environment
    if [[ -z $test_root ]]; then
        [[ ${EUID} -eq 0 ]] || { echo 'The Face ID removal transaction requires administrator access.' >&2; exit 1; }
        findmnt -nro OPTIONS --target "$0" 2>/dev/null | tr ',' '\n' | grep -Fxq ro \
            || { echo 'Face ID removal must run directly from the read-only AppImage.' >&2; exit 1; }
    fi
    install() {
        if [[ -z $test_root ]]; then command install "$@"; return; fi
        local -a clean=()
        while (($#)); do
            case $1 in -o|-g) shift 2 ;; *) clean+=("$1"); shift ;; esac
        done
        command install "${clean[@]}"
    }
    [[ $root_user_id =~ ^[0-9]+$ && $root_last_user =~ ^[01]$ \
        && $root_gaze_owned =~ ^[01]$ && $root_camera_owned =~ ^[01]$ \
        && ( $root_sudo_integration == none || $root_sudo_integration == added \
             || $root_sudo_integration == restore ) ]] \
        || { echo 'Invalid Face ID removal metadata.' >&2; exit 1; }

    local user_registry="$user_registry_dir/$root_user_id"
    [[ -f $user_registry && $(<"$user_registry") == "$user_registry_value" ]] \
        || { echo 'The Face ID user registration could not be verified.' >&2; exit 1; }
    if ((root_last_user)); then
        local entry
        while IFS= read -r entry; do
            [[ $entry == "$user_registry" ]] && continue
            echo 'Another registered user still needs the shared Face ID components.' >&2
            exit 1
        done < <(find "$user_registry_dir" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
    fi

    install -d -o root -g root -m 0755 "$ownership_dir"
    local lock_file="$ownership_dir/install.lock"
    [[ -e $lock_file ]] || install -o root -g root -m 0600 /dev/null "$lock_file"
    exec {lock_fd}<>"$lock_file"
    flock -x "$lock_fd"

    local transaction_dir="$ownership_dir/transactions/uninstall-$$"
    local transaction_active=0 root_step_count=0
    local -a paths=("$user_registry") existed=()
    if ((root_last_user)); then
        paths+=("$sudo_pam_file" "$face_id_pam_file" "$verifier_pam_file" "$elevation_target"
            "$consent_target" "$sudo_integration_receipt" "$gaze_receipt"
            "$camera_support_receipt" "$pam_target")
    fi
    checkpoint() {
        ((root_step_count+=1))
        if [[ -n $test_root && ${OMARCHY_FACE_ID_FAIL_ROOT_STEP:-0} -eq $root_step_count ]]; then exit 97; fi
    }
    rollback() {
        local index
        for ((index=0; index<${#paths[@]}; index++)); do
            rm -f -- "${paths[$index]}" >/dev/null 2>&1 || true
            [[ ${existed[$index]} == 1 ]] \
                && cp -a -- "$transaction_dir/$index" "${paths[$index]}" >/dev/null 2>&1 || true
        done
        rm -rf -- "$transaction_dir" >/dev/null 2>&1 || true
    }
    root_finish() {
        local status=$?
        trap - EXIT
        if ((status != 0 && transaction_active)); then rollback; fi
        if [[ -n $test_root ]]; then printf '%s\n' "$root_step_count" >"$test_root/uninstall-root-step-count"; fi
        exit "$status"
    }
    trap root_finish EXIT
    install -d -o root -g root -m 0700 "$ownership_dir/transactions"; checkpoint
    install -d -o root -g root -m 0700 "$transaction_dir"; checkpoint
    local index=0 path
    for path in "${paths[@]}"; do
        if [[ -e $path || -L $path ]]; then cp -a -- "$path" "$transaction_dir/$index"; existed+=(1); else existed+=(0); fi
        checkpoint
        ((index+=1))
    done
    transaction_active=1

    if ((root_last_user)); then
        [[ $root_sudo_integration != none ]] || { echo 'The sudo integration receipt is missing.' >&2; exit 1; }
        [[ -f $face_id_pam_file ]] \
            && grep -Fqx '# Omarchy Face ID sudo authentication. Managed by Omarchy Face ID.' "$face_id_pam_file" \
            || { echo 'The dedicated Face ID PAM file is not managed by Face ID.' >&2; exit 1; }
        [[ -f $verifier_pam_file ]] \
            && grep -Fqx '# Omarchy Face ID private face verification. Managed by Omarchy Face ID.' "$verifier_pam_file" \
            || { echo 'The private Face ID verifier PAM file is not managed by Face ID.' >&2; exit 1; }
        [[ -f $pam_target ]] && grep -q '^# Face-only service for Omarchy Face ID\.' "$pam_target" \
            || { echo 'The lock-screen PAM file is not managed by Face ID.' >&2; exit 1; }

        local work_dir="$transaction_dir/work" sudo_temp="$transaction_dir/work/sudo"
        install -d -o root -g root -m 0700 "$work_dir"; checkpoint
        local restore_gaze=0
        [[ $root_sudo_integration == restore && $root_gaze_owned -eq 0 ]] && restore_gaze=1
        if ! awk -v begin='# BEGIN Omarchy Face ID sudo' -v end='# END Omarchy Face ID sudo' -v restore="$restore_gaze" '
            $0 == begin { managed=1; next } $0 == end { managed=0; next } managed { next }
            !inserted && restore == 1 && $1 == "auth" && ($2 == "include" || $2 == "substack") && $3 == "system-auth" { print "auth sufficient pam_gaze.so"; inserted=1 }
            { print } END { if (restore == 1 && !inserted) exit 42 }
        ' "$sudo_pam_file" >"$sudo_temp"; then
            echo 'The sudo authentication layout is not supported.' >&2
            exit 1
        fi
        grep -Eq '^auth[[:space:]]+(include|substack)[[:space:]]+system-auth' "$sudo_temp" \
            || { echo 'The password authentication rule would be lost.' >&2; exit 1; }
        install -o root -g root -m 0644 "$sudo_temp" "$sudo_pam_file.omarchy-face-id-new.$$"; checkpoint
        mv -f -- "$sudo_pam_file.omarchy-face-id-new.$$" "$sudo_pam_file"; checkpoint
        rm -f -- "$face_id_pam_file" "$verifier_pam_file" "$elevation_target" "$consent_target" \
            "$sudo_integration_receipt" "$pam_target"; checkpoint
        ((root_gaze_owned)) && rm -f -- "$gaze_receipt"
        ((root_camera_owned)) && rm -f -- "$camera_support_receipt"
        ! grep -Fqx 'auth include omarchy-face-id' "$sudo_pam_file" \
            || { echo 'Face ID could not be removed from sudo.' >&2; exit 1; }
    fi
    rm -f -- "$user_registry"; checkpoint
    rm -rf -- "$transaction_dir"
    transaction_active=0
    if ((root_last_user)); then
        rmdir "$verifier_pam_dir" 2>/dev/null || true
        rmdir "${verifier_pam_dir%/*}" 2>/dev/null || true
    fi
    if [[ -n $test_root ]]; then printf '%s\n' "$root_step_count" >"$test_root/uninstall-root-step-count"; fi
    trap - EXIT
}

usage() {
    printf '%s\n' 'Usage: Omarchy_Face_ID-<version>-x86_64.AppImage --uninstall [--yes]' '' \
        'Remove this user’s Face ID enrollment and lock-screen integration.' \
        'Shared components are removed only after the last registered user leaves.'
}
while (($# > 0)); do
    case "$1" in
        --root-remove) root_mode=1 ;;
        --user-id) shift; root_user_id=${1:-} ;;
        --last-user) shift; root_last_user=${1:-} ;;
        --sudo-integration) shift; root_sudo_integration=${1:-} ;;
        --gaze-owned) shift; root_gaze_owned=${1:-} ;;
        --camera-owned) shift; root_camera_owned=${1:-} ;;
        --yes|-y) assume_yes=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done
if ((root_mode)); then
    root_remove
    exit 0
fi
if [[ ${EUID} -eq 0 ]]; then echo 'Run this as your normal user; it requests sudo only for system files.' >&2; exit 1; fi
guard_test_environment

if [[ ${OMARCHY_FACE_ID_SKIP_LOCK_CHECK:-0} != 1 ]] && command -v omarchy-hyprland-session-locked >/dev/null 2>&1 && omarchy-hyprland-session-locked >/dev/null 2>&1; then
    echo 'Unlock the computer before uninstalling Omarchy Face ID.' >&2; exit 1
fi

gaze_ownership=none
if [[ -f $gaze_receipt ]]; then case $(<"$gaze_receipt") in "$expected_gaze_receipt") gaze_ownership=legacy ;; "$expected_gaze_aur_receipt") gaze_ownership=aur ;; esac; fi
gaze_owned=0; [[ $gaze_ownership == none ]] || gaze_owned=1
camera_support_owned=0
if [[ -f $camera_support_receipt ]] && [[ $(<"$camera_support_receipt") == "$expected_camera_support_receipt" ]]; then camera_support_owned=1; fi
sudo_integration=none
if [[ -f $sudo_integration_receipt ]]; then
    case $(<"$sudo_integration_receipt") in "$expected_sudo_added") sudo_integration=added ;; "$expected_sudo_replaced") sudo_integration=restore ;; *) echo 'The sudo integration receipt is invalid; sudo was left unchanged.' >&2; exit 1 ;; esac
fi

sudo_begin='# BEGIN Omarchy Face ID sudo'; sudo_end='# END Omarchy Face ID sudo'
hook_line='auth include omarchy-face-id'
begin_count=$(grep -Fxc "$sudo_begin" "$sudo_pam_file" 2>/dev/null || true)
end_count=$(grep -Fxc "$sudo_end" "$sudo_pam_file" 2>/dev/null || true)
((begin_count <= 1 && end_count <= 1 && begin_count == end_count)) || { echo 'The sudo integration is incomplete; sudo was left unchanged.' >&2; exit 1; }
if [[ -e $face_id_pam_file ]] && ! grep -Fqx '# Omarchy Face ID sudo authentication. Managed by Omarchy Face ID.' "$face_id_pam_file"; then
    echo "$face_id_pam_file is not managed by Omarchy Face ID; it was left unchanged." >&2; exit 1
fi
if [[ -e $verifier_pam_file ]] && ! grep -Fqx '# Omarchy Face ID private face verification. Managed by Omarchy Face ID.' "$verifier_pam_file"; then
    echo "$verifier_pam_file is not managed by Omarchy Face ID; it was left unchanged." >&2; exit 1
fi

face_name=""
if [[ -f $face_receipt ]]; then face_name=$(<"$face_receipt")
elif [[ -f $plugin_target/manifest.json ]] && grep -Fq '"id": "fitzzz.face-id"' "$plugin_target/manifest.json"; then face_name=default
fi
if [[ -n $face_name && ! $face_name =~ ^[A-Za-z0-9._-]+$ ]]; then echo 'The enrollment receipt is invalid; no face data was changed.' >&2; exit 1; fi
if [[ -e $pam_target ]] && ! grep -q '^# Face-only service for Omarchy Face ID\.' "$pam_target"; then echo "$pam_target is not managed by Omarchy Face ID; it was left unchanged." >&2; exit 1; fi

user_id=$(id -u); user_registry="$user_registry_dir/$user_id"
registered_user=0
if [[ -f $user_registry ]] && [[ $(<"$user_registry") == "$user_registry_value" ]]; then registered_user=1
elif [[ -e $user_registry || -L $user_registry ]]; then echo 'The Face ID user registration is invalid; shared components were left unchanged.' >&2; exit 1
fi
remaining_users=0
if [[ -d $user_registry_dir ]]; then
    while IFS= read -r entry; do
        [[ $entry == "$user_registry" ]] && continue
        # Unknown entries are counted conservatively: they can never cause data removal.
        ((remaining_users+=1))
    done < <(find "$user_registry_dir" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
fi
last_registered_user=0
if ((registered_user && remaining_users == 0)); then last_registered_user=1; fi

if ((assume_yes == 0)); then
    [[ -t 0 && -t 1 ]] || { echo 'Run interactively or pass --yes.' >&2; exit 1; }
    echo 'Face ID and this user’s saved face scan will be removed.'
    echo 'Your password will not change.'
    ((last_registered_user)) && echo 'Shared components installed by Face ID will also be removed.'
    read -r -p 'Continue? [y/N] ' answer; [[ $answer == y || $answer == Y ]] || exit 0
fi

account_name=$(id -un)
if [[ -n $face_name ]] && command -v gaze >/dev/null 2>&1; then
    if gaze list-faces --user "$account_name" 2>/dev/null | grep -Fq "• $face_name "; then gaze remove-face "$face_name" --user "$account_name"; fi
fi
if [[ -e $plugin_target || -L $plugin_target ]]; then
    [[ -f $plugin_target/manifest.json ]] && grep -Fq '"id": "fitzzz.face-id"' "$plugin_target/manifest.json" || { echo "$plugin_target is not a recognized Omarchy Face ID plugin; it was left unchanged." >&2; exit 1; }
    omarchy plugin remove "$plugin_id" --yes
fi
if [[ -f $face_receipt ]]; then unlink "$face_receipt"; fi
rmdir "$state_dir" 2>/dev/null || true

# A missing legacy registration cannot prove that no other user is enrolled.
# In that case shared state is deliberately preserved.
if ((last_registered_user == 0)); then
    if ((registered_user)); then
        sudo "$0" --root-remove --user-id "$user_id" --last-user 0 \
            --sudo-integration "$sudo_integration" --gaze-owned "$gaze_owned" \
            --camera-owned "$camera_support_owned"
    fi
    echo 'Face ID was removed for this user. Your password is unchanged.'
    ((registered_user == 0)) && echo 'Shared components were kept because no safe user-registration record was available.'
    exit 0
fi

# The trusted AppImage script owns the complete final-user system transaction.
# It removes the sudo hook before any referenced helper or PAM module.
sudo "$0" --root-remove --user-id "$user_id" --last-user 1 \
    --sudo-integration "$sudo_integration" --gaze-owned "$gaze_owned" \
    --camera-owned "$camera_support_owned"

# Package cleanup happens only after password sudo is independent of Face ID.
# Failure here leaves an unused package behind; it cannot damage authentication.
if ((gaze_owned)); then
    if [[ $gaze_ownership == aur ]] && command -v gaze >/dev/null 2>&1; then gaze uninstall --yes
    elif [[ $gaze_ownership == aur ]] && pacman -Q gaze-bin >/dev/null 2>&1; then sudo systemctl disable --now gazed.service >/dev/null 2>&1 || true; omarchy pkg drop gaze-bin
    elif pacman -Q gaze >/dev/null 2>&1; then sudo systemctl disable --now gazed.service >/dev/null 2>&1 || true; sudo pacman -Rns --noconfirm gaze
    fi
fi
if ((camera_support_owned)) && pacman -Q gst-plugins-good >/dev/null 2>&1; then
    if ! omarchy pkg drop gst-plugins-good; then
        echo 'Camera support is still needed by another package, so it was kept.'
    fi
fi

sudo rmdir "$user_registry_dir" 2>/dev/null || true
sudo rmdir "$ownership_dir/transactions" 2>/dev/null || true
sudo rmdir "$ownership_dir" 2>/dev/null || true
echo 'Face ID was removed. Your password is unchanged.'
