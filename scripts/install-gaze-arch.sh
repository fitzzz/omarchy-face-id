#!/usr/bin/env bash
set -euo pipefail

ownership_dir="${OMARCHY_FACE_ID_OWNERSHIP_DIR:-/var/lib/omarchy-face-id}"
gaze_receipt="$ownership_dir/gaze-installed"
camera_receipt="$ownership_dir/camera-support-installed"
sudo_receipt="$ownership_dir/sudo-integration"
user_registry_dir="$ownership_dir/users"
sudo_pam_file="${OMARCHY_FACE_ID_SUDO_PAM_PATH:-/etc/pam.d/sudo}"
face_pam_file="${OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH:-${sudo_pam_file%/*}/omarchy-face-id}"
polkit_pam_file="${OMARCHY_FACE_ID_POLKIT_PAM_PATH:-/etc/pam.d/polkit-1}"
polkit_marker="${OMARCHY_FACE_ID_GAZE_POLKIT_MARKER:-/etc/gaze/pam-arch.polkit-configured}"
elevation_target="${OMARCHY_FACE_ID_ELEVATION_TARGET:-/usr/libexec/omarchy-face-id-elevation}"
consent_target="${OMARCHY_FACE_ID_CONSENT_TARGET:-/usr/lib/security/pam_omarchy_face_id_consent.so}"
verifier_pam_dir="${OMARCHY_FACE_ID_VERIFY_PAM_DIR:-/usr/lib/omarchy-face-id/pam.d}"
verifier_pam_file="$verifier_pam_dir/sudo"
test_root="${OMARCHY_FACE_ID_TEST_ROOT:-}"
gaze_value='omarchy-face-id:gaze-aur:gaze-bin'
legacy_gaze_value='omarchy-face-id:gaze:0.2.12-1'
camera_value='omarchy-face-id:camera-support:gst-plugins-good'
sudo_added='omarchy-face-id:sudo:added'
sudo_replaced='omarchy-face-id:sudo:restore-gaze'
user_value='omarchy-face-id:registered-user:1'
sudo_begin='# BEGIN Omarchy Face ID sudo'
sudo_end='# END Omarchy Face ID sudo'
hook_line='auth include omarchy-face-id'

# Production integration has one fixed system footprint. Path overrides exist
# only for the guarded fake-root test harness.
if [[ -z $test_root ]]; then
    ownership_dir=/var/lib/omarchy-face-id
    gaze_receipt="$ownership_dir/gaze-installed"
    camera_receipt="$ownership_dir/camera-support-installed"
    sudo_receipt="$ownership_dir/sudo-integration"
    user_registry_dir="$ownership_dir/users"
    sudo_pam_file=/etc/pam.d/sudo
    face_pam_file=/etc/pam.d/omarchy-face-id
    polkit_pam_file=/etc/pam.d/polkit-1
    polkit_marker=/etc/gaze/pam-arch.polkit-configured
    elevation_target=/usr/libexec/omarchy-face-id-elevation
    consent_target=/usr/lib/security/pam_omarchy_face_id_consent.so
    verifier_pam_dir=/usr/lib/omarchy-face-id/pam.d
    verifier_pam_file="$verifier_pam_dir/sudo"
fi

guard_paths() {
    [[ -z $test_root ]] && return 0
    [[ $test_root == /tmp/* && -d $test_root ]] || { echo 'Unsafe Face ID test root.' >&2; exit 2; }
    local path
    for path in "$ownership_dir" "$sudo_pam_file" "$face_pam_file" "$polkit_pam_file" "$polkit_marker" "$elevation_target" "$consent_target" "$verifier_pam_dir" "$verifier_pam_file"; do
        [[ $path == "$test_root"/* ]] || { echo "Refusing live system path during a sandboxed test: $path" >&2; exit 2; }
    done
}

root_integrate() {
    local helper=$1 helper_sha=$2 module=$3 module_sha=$4 user_id=$5 restore_gaze=$6 gaze_owned=$7 camera_owned=$8 managed_gaze=$9
    guard_paths
    if [[ -z $test_root && ${EUID} -ne 0 ]]; then echo 'The Face ID system transaction requires administrator access.' >&2; exit 1; fi
    install() {
        if [[ -z $test_root ]]; then command install "$@"; return; fi
        local -a clean=()
        while (($#)); do
            case $1 in -o|-g) shift 2 ;; *) clean+=("$1"); shift ;; esac
        done
        command install "${clean[@]}"
    }
    [[ $helper_sha =~ ^[0-9a-f]{64}$ && $module_sha =~ ^[0-9a-f]{64}$ ]] || { echo 'Invalid Face ID payload digest.' >&2; exit 1; }
    [[ $user_id =~ ^[0-9]+$ && $restore_gaze =~ ^[01]$ && $gaze_owned =~ ^[01]$ && $camera_owned =~ ^[01]$ && $managed_gaze =~ ^[01]$ ]] || { echo 'Invalid Face ID transaction metadata.' >&2; exit 1; }
    [[ $helper == /* && -f $helper && ! -L $helper && -x $helper ]] || { echo 'The Face ID elevation bridge is unavailable.' >&2; exit 1; }
    [[ $module == /* && -f $module && ! -L $module && -r $module ]] || { echo 'The Face ID consent module is unavailable.' >&2; exit 1; }
    local stream_dir=''
    if [[ ${OMARCHY_FACE_ID_ROOT_STREAM:-} == 1 ]]; then
        stream_dir=${helper%/*}
        if [[ -n $test_root ]]; then
            [[ $stream_dir == "$test_root"/root-stream.* \
                && ${module%/*} == "$stream_dir" ]] \
                || { echo 'The Face ID test root handoff is invalid.' >&2; exit 1; }
        else
            [[ $stream_dir == /run/omarchy-face-id-install.* \
                && ${module%/*} == "$stream_dir" ]] \
                || { echo 'The Face ID root handoff is invalid.' >&2; exit 1; }
            local stream_owner stream_mode
            stream_owner=$(stat -c '%u' "$stream_dir" 2>/dev/null || true)
            stream_mode=$(stat -c '%a' "$stream_dir" 2>/dev/null || true)
            [[ $stream_owner == 0 && $stream_mode == 700 ]] \
                || { echo 'The Face ID root handoff is not protected.' >&2; exit 1; }
        fi
    elif [[ -z $test_root ]]; then
        echo 'Face ID privileged payloads must use the private root handoff.' >&2
        exit 1
    fi

    # Open before hashing and copy from these descriptors only. Production
    # callers provide immutable AppImage files; the digest binds exact bytes.
    exec {helper_fd}<"$helper"; exec {module_fd}<"$module"
    local helper_source="/proc/$$/fd/$helper_fd" module_source="/proc/$$/fd/$module_fd"
    [[ $(sha256sum "$helper_source" | cut -d' ' -f1) == "$helper_sha" ]] || { echo 'The elevation bridge failed verification.' >&2; exit 1; }
    [[ $(sha256sum "$module_source" | cut -d' ' -f1) == "$module_sha" ]] || { echo 'The consent module failed verification.' >&2; exit 1; }

    install -d -o root -g root -m 0755 "$ownership_dir"
    local lock_file="$ownership_dir/install.lock"
    [[ -e $lock_file ]] || install -o root -g root -m 0600 /dev/null "$lock_file"
    exec {lock_fd}<>"$lock_file"; flock -x "$lock_fd"

    local transaction_dir="$ownership_dir/transactions/$$" transaction_active=0 root_step_count=0
    local -a paths=("$sudo_pam_file" "$face_pam_file" "$verifier_pam_file" "$elevation_target" "$consent_target" "$sudo_receipt" \
        "$user_registry_dir/$user_id" "$user_registry_dir/.legacy-unknown" "$polkit_pam_file" "$gaze_receipt" "$camera_receipt")
    local -a existed=()
    checkpoint() {
        ((root_step_count+=1))
        if [[ -n $test_root && ${OMARCHY_FACE_ID_FAIL_ROOT_STEP:-0} -eq $root_step_count ]]; then exit 97; fi
    }
    rollback() {
        local i
        for ((i=0; i<${#paths[@]}; i++)); do
            rm -f -- "${paths[$i]}" >/dev/null 2>&1 || true
            [[ ${existed[$i]} == 1 ]] && cp -a -- "$transaction_dir/$i" "${paths[$i]}" >/dev/null 2>&1 || true
        done
        rm -rf -- "$transaction_dir" >/dev/null 2>&1 || true
    }
    root_finish() {
        local status=$?
        trap - EXIT
        if ((status != 0 && transaction_active)); then rollback; fi
        [[ -z $stream_dir ]] || rm -rf -- "$stream_dir"
        if [[ -n $test_root ]]; then printf '%s\n' "$root_step_count" >"$test_root/root-step-count"; fi
        exit "$status"
    }
    trap root_finish EXIT
    install -d -o root -g root -m 0700 "$ownership_dir/transactions"; checkpoint
    install -d -o root -g root -m 0700 "$transaction_dir"; checkpoint
    local i=0 path
    for path in "${paths[@]}"; do
        if [[ -e $path || -L $path ]]; then cp -a -- "$path" "$transaction_dir/$i"; existed+=(1); else existed+=(0); fi
        checkpoint; ((i+=1))
    done
    transaction_active=1

    if [[ -e $elevation_target || -L $elevation_target ]]; then
        [[ -f $elevation_target && ! -L $elevation_target ]] \
            && { grep -aFq 'Omarchy Face ID elevation bridge 1' "$elevation_target" \
                || grep -aFq 'Omarchy Face ID elevation helper 2' "$elevation_target"; } \
            || { echo "$elevation_target is not managed by Omarchy Face ID." >&2; exit 1; }
    fi
    if [[ -e $consent_target || -L $consent_target ]]; then
        [[ -f $consent_target && ! -L $consent_target ]] && grep -aFq 'Omarchy Face ID consent module 1' "$consent_target" || { echo "$consent_target is not managed by Omarchy Face ID." >&2; exit 1; }
    fi
    if [[ -e $face_pam_file || -L $face_pam_file ]]; then
        [[ -f $face_pam_file && ! -L $face_pam_file ]] && grep -Fqx '# Omarchy Face ID sudo authentication. Managed by Omarchy Face ID.' "$face_pam_file" || { echo "$face_pam_file is not managed by Omarchy Face ID." >&2; exit 1; }
    fi
    if [[ -e $verifier_pam_file || -L $verifier_pam_file ]]; then
        [[ -f $verifier_pam_file && ! -L $verifier_pam_file ]] \
            && grep -Fqx '# Omarchy Face ID private face verification. Managed by Omarchy Face ID.' "$verifier_pam_file" \
            || { echo "$verifier_pam_file is not managed by Omarchy Face ID." >&2; exit 1; }
    fi
    local begin_count end_count legacy_unknown=0
    begin_count=$(grep -Fxc "$sudo_begin" "$sudo_pam_file" 2>/dev/null || true); end_count=$(grep -Fxc "$sudo_end" "$sudo_pam_file" 2>/dev/null || true)
    ((begin_count <= 1 && end_count <= 1 && begin_count == end_count)) || { echo 'The existing sudo integration is incomplete.' >&2; exit 1; }
    [[ ! -d $user_registry_dir && ( -f $sudo_receipt || $begin_count -eq 1 ) ]] && legacy_unknown=1

    local work_dir="$transaction_dir/work"; install -d -o root -g root -m 0700 "$work_dir"; checkpoint
    local sudo_temp="$work_dir/sudo" face_temp="$work_dir/omarchy-face-id" verifier_temp="$work_dir/verify-sudo"
    if ! awk -v begin="$sudo_begin" -v end="$sudo_end" -v hook="$hook_line" '
        $0 == begin { managed=1; next } $0 == end { managed=0; next } managed { next }
        $1 == "auth" && $2 == "sufficient" && $3 == "pam_gaze.so" && NF == 3 { next }
        !inserted && $1 == "auth" && ($2 == "include" || $2 == "substack") && $3 == "system-auth" { print begin; print hook; print end; inserted=1 }
        { print } END { if (!inserted) exit 42 }
    ' "$sudo_pam_file" >"$sudo_temp"; then echo 'The sudo authentication layout is unsupported.' >&2; exit 1; fi
    printf '%s\n' '# Omarchy Face ID sudo authentication. Managed by Omarchy Face ID.' \
        "auth [success=done auth_err=die default=ignore] pam_omarchy_face_id_consent.so helper=$elevation_target" >"$face_temp"
    printf '%s\n' '# Omarchy Face ID private face verification. Managed by Omarchy Face ID.' \
        'auth [success=done ignore=ignore default=bad] pam_gaze.so' \
        'auth required pam_deny.so' \
        'account required pam_permit.so' >"$verifier_temp"

    atomic_copy() {
        local source=$1 expected=$2 target=$3 mode=$4 temp
        temp="$target.omarchy-face-id-new.$$"
        install -d -o root -g root -m 0755 "${target%/*}"
        [[ $(sha256sum "$source" | cut -d' ' -f1) == "$expected" ]] || return 1
        install -o root -g root -m "$mode" "$source" "$temp"; checkpoint
        [[ $(sha256sum "$temp" | cut -d' ' -f1) == "$expected" ]] || return 1
        mv -f -- "$temp" "$target"; checkpoint
    }
    atomic_text() {
        local value=$1 target=$2 mode=${3:-0644} source
        source="$work_dir/text-$root_step_count"
        printf '%s\n' "$value" >"$source"
        atomic_copy "$source" "$(sha256sum "$source" | cut -d' ' -f1)" "$target" "$mode"
    }

    atomic_copy "$helper_source" "$helper_sha" "$elevation_target" 0755
    atomic_copy "$module_source" "$module_sha" "$consent_target" 0644
    atomic_copy "$verifier_temp" "$(sha256sum "$verifier_temp" | cut -d' ' -f1)" "$verifier_pam_file" 0644
    atomic_copy "$face_temp" "$(sha256sum "$face_temp" | cut -d' ' -f1)" "$face_pam_file" 0644
    if ((managed_gaze)) && [[ -r $polkit_pam_file && -r $polkit_marker && $(<"$polkit_marker") == "$polkit_pam_file" ]]; then
        awk '!($1 == "auth" && $2 == "sufficient" && $3 == "pam_gaze.so" && NF == 3)' "$polkit_pam_file" >"$work_dir/polkit"
        atomic_copy "$work_dir/polkit" "$(sha256sum "$work_dir/polkit" | cut -d' ' -f1)" "$polkit_pam_file" 0644
    fi
    atomic_text "$([[ $restore_gaze == 1 ]] && echo "$sudo_replaced" || echo "$sudo_added")" "$sudo_receipt"
    install -d -o root -g root -m 0755 "$user_registry_dir"; checkpoint
    atomic_text "$user_value" "$user_registry_dir/$user_id"
    if ((legacy_unknown)); then atomic_text "$user_value" "$user_registry_dir/.legacy-unknown"; fi
    if ((gaze_owned)); then atomic_text "$gaze_value" "$gaze_receipt"; fi
    if ((camera_owned)); then atomic_text "$camera_value" "$camera_receipt"; fi
    # Expose the hook last, only after every referenced artifact is complete.
    atomic_copy "$sudo_temp" "$(sha256sum "$sudo_temp" | cut -d' ' -f1)" "$sudo_pam_file" 0644

    grep -Fqx "$hook_line" "$sudo_pam_file" && ! grep -Fq pam_gaze.so "$face_pam_file" \
        && grep -Fqx 'auth [success=done ignore=ignore default=bad] pam_gaze.so' "$verifier_pam_file" \
        && [[ $(<"$user_registry_dir/$user_id") == "$user_value" ]] \
        && [[ $(sha256sum "$elevation_target" | cut -d' ' -f1) == "$helper_sha" ]] \
        && [[ $(sha256sum "$consent_target" | cut -d' ' -f1) == "$module_sha" ]] \
        || { echo 'Face ID validation failed; restoring the previous configuration.' >&2; exit 1; }
    checkpoint
    rm -rf -- "$transaction_dir"; transaction_active=0
    [[ -z $stream_dir ]] || rm -rf -- "$stream_dir"
    if [[ -n $test_root ]]; then printf '%s\n' "$root_step_count" >"$test_root/root-step-count"; fi
    trap - EXIT
}

stream_root_integrate() {
    local helper=$1 helper_sha=$2 module=$3 module_sha=$4 user_id=$5 restore_gaze=$6 gaze_owned=$7 camera_owned=$8 managed_gaze=$9
    local stream_template=/run/omarchy-face-id-install.XXXXXX
    [[ -z $test_root ]] || stream_template="$test_root/root-stream.XXXXXX"

    # Root cannot reopen a desktop user's FUSE-mounted AppImage on standard
    # systems. Send the already-verified read-only payload over one anonymous
    # pipe instead. The privileged side writes root-owned files, verifies their
    # hashes, performs the existing transaction, and removes the handoff on exit.
    {
        printf '%s\n' 'set -euo pipefail'
        printf 'stream_dir=$(mktemp -d %q)\n' "$stream_template"
        printf '%s\n' 'chmod 0700 "$stream_dir"' \
            'base64 -d >"$stream_dir/elevation" <<'\''__OMARCHY_ELEVATION_PAYLOAD__'\'''
        base64 "$helper"
        printf '%s\n' '__OMARCHY_ELEVATION_PAYLOAD__' \
            'base64 -d >"$stream_dir/consent.so" <<'\''__OMARCHY_CONSENT_PAYLOAD__'\'''
        base64 "$module"
        printf '%s\n' '__OMARCHY_CONSENT_PAYLOAD__' \
            'chmod 0755 "$stream_dir/elevation"' \
            'chmod 0644 "$stream_dir/consent.so"' \
            'export OMARCHY_FACE_ID_ROOT_STREAM=1'
        printf 'set -- --root-integrate --elevation-helper "$stream_dir/elevation" --elevation-sha256 %q ' "$helper_sha"
        printf '%s ' '--consent-module' '"$stream_dir/consent.so"' '--consent-sha256'
        printf '%q ' "$module_sha" '--user-id' "$user_id" '--restore-gaze' "$restore_gaze" \
            '--gaze-owned' "$gaze_owned" '--camera-owned' "$camera_owned" '--managed-gaze' "$managed_gaze"
        printf '\n'
        cat "$0"
    } | sudo /usr/bin/bash -s
}

root_mode=0 elevation_helper='' consent_module='' elevation_sha='' consent_sha='' root_user_id='' root_restore='' root_gaze_owned='' root_camera_owned='' root_managed=''
status_file='' self_delete=0 wizard_mode=0
while (($# > 0)); do
    case "$1" in
        --root-integrate) root_mode=1 ;;
        --elevation-helper) shift; elevation_helper=${1:-} ;;
        --elevation-sha256) shift; elevation_sha=${1:-} ;;
        --consent-module) shift; consent_module=${1:-} ;;
        --consent-sha256) shift; consent_sha=${1:-} ;;
        --user-id) shift; root_user_id=${1:-} ;;
        --restore-gaze) shift; root_restore=${1:-} ;;
        --gaze-owned) shift; root_gaze_owned=${1:-} ;;
        --camera-owned) shift; root_camera_owned=${1:-} ;;
        --managed-gaze) shift; root_managed=${1:-} ;;
        --status-file) shift; status_file=${1:-}; [[ $status_file == /tmp/omarchy-face-id-install.* ]] || { echo 'Invalid setup status path.' >&2; exit 2; } ;;
        --self-delete) self_delete=1 ;;
        --wizard) wizard_mode=1 ;;
        --help|-h) echo 'Usage: install-gaze-arch.sh --elevation-helper PATH --elevation-sha256 SHA256 --consent-module PATH --consent-sha256 SHA256'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
if ((root_mode)); then
    root_integrate "$elevation_helper" "$elevation_sha" "$consent_module" "$consent_sha" "$root_user_id" "$root_restore" "$root_gaze_owned" "$root_camera_owned" "$root_managed"
    exit 0
fi

finish() {
    local status=$?; trap - EXIT
    if ((status != 0 && ${integration_committed:-0} == 0)); then
        ((${gaze_owned:-0})) && omarchy pkg drop gaze-bin >/dev/null 2>&1 || true
        ((${camera_owned:-0})) && omarchy pkg drop gst-plugins-good >/dev/null 2>&1 || true
    fi
    if [[ -n $status_file ]]; then local temp="${status_file}.tmp.$$"; ((status == 0)) && echo success >"$temp" || echo failure >"$temp"; mv -f -- "$temp" "$status_file"; fi
    ((self_delete)) && rm -f -- "$0"
    exit "$status"
}
trap finish EXIT
integration_committed=0
[[ ${EUID} -ne 0 ]] || { echo 'Run this as your normal user.' >&2; exit 1; }
guard_paths
for command_name in omarchy pacman sudo systemctl sha256sum base64; do command -v "$command_name" >/dev/null || { echo "Face ID setup needs $command_name." >&2; exit 1; }; done
if [[ -n $test_root ]]; then
    for command_name in omarchy pacman sudo systemctl; do [[ $(command -v "$command_name") == "$test_root"/bin/* ]] || { echo "Refusing live command: $command_name" >&2; exit 2; }; done
fi
[[ -f $elevation_helper && ! -L $elevation_helper && -x $elevation_helper && -f $consent_module && ! -L $consent_module ]] || { echo 'Face ID payloads are unavailable.' >&2; exit 1; }
[[ $(sha256sum "$elevation_helper" | cut -d' ' -f1) == "$elevation_sha" && $(sha256sum "$consent_module" | cut -d' ' -f1) == "$consent_sha" ]] || { echo 'Face ID payload verification failed.' >&2; exit 1; }

gaze_missing=1; pacman -Q gaze-bin >/dev/null 2>&1 && gaze_missing=0
camera_preexisting=0; pacman -Q gst-plugins-good >/dev/null 2>&1 && camera_preexisting=1
camera_missing=1; command -v gst-inspect-1.0 >/dev/null && gst-inspect-1.0 jpegdec >/dev/null 2>&1 && camera_missing=0
if ((wizard_mode)); then clear 2>/dev/null || true; ((gaze_missing)) && printf '\n  Installing Gaze…\n\n' || printf '\n  Starting Face ID…\n\n'; fi
camera_owned=0
if ((camera_missing)); then omarchy pkg add gst-plugins-good; ((camera_preexisting == 0)) && camera_owned=1; fi
command -v gst-inspect-1.0 >/dev/null && gst-inspect-1.0 jpegdec >/dev/null 2>&1 || { echo 'Required camera-format support is unavailable.' >&2; exit 1; }
gaze_owned=0
if ((gaze_missing)); then omarchy pkg aur add gaze-bin; gaze_owned=1; fi
sudo systemctl enable gazed.service; sudo systemctl restart gazed.service

managed_gaze=0
if ((gaze_owned)) || { [[ -f $gaze_receipt ]] && { [[ $(<"$gaze_receipt") == "$gaze_value" ]] || [[ $(<"$gaze_receipt") == "$legacy_gaze_value" ]]; }; }; then managed_gaze=1; fi
restore_gaze=0
if [[ -f $sudo_receipt ]]; then
    case $(<"$sudo_receipt") in "$sudo_added") restore_gaze=0 ;; "$sudo_replaced") restore_gaze=1 ;; *) echo 'Invalid sudo integration receipt.' >&2; exit 1 ;; esac
elif grep -Eq '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_gaze\.so[[:space:]]*$' "$sudo_pam_file" 2>/dev/null && ((managed_gaze == 0)); then restore_gaze=1
fi

set +e
stream_root_integrate "$elevation_helper" "$elevation_sha" "$consent_module" "$consent_sha" "$(id -u)" \
    "$restore_gaze" "$gaze_owned" "$camera_owned" "$managed_gaze"
integration_status=$?
set -e
if ((integration_status != 0)); then exit "$integration_status"; fi
integration_committed=1
((wizard_mode)) && printf '\n  ✓ Face ID is ready. Returning to setup…\n' || printf 'Face ID system setup is complete.\n'
