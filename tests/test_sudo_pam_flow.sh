#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
harness=${1:?PAM harness is required}
bridge=${2:?elevation helper is required}
consent_module=${3:?consent PAM module is required}
temporary_dir=$(mktemp -d -t face-id-pam-flow.XXXXXX)
cleanup() {
    local status=$?
    if [[ $status -ne 0 && ${OMARCHY_FACE_ID_KEEP_TEST_ROOT:-0} == 1 ]]; then
        printf 'Preserved failed PAM root: %s\n' "$temporary_dir" >&2
    else
        rm -rf -- "$temporary_dir"
    fi
}
trap cleanup EXIT

[[ $temporary_dir == /tmp/face-id-pam-flow.* ]]
[[ $harness != /usr/* && $bridge != /usr/* && $consent_module != /usr/* ]]
source_module="$project_root/elevation/pam_consent.c"
grep -Fq 'sd_uid_get_sessions' "$source_module"
if grep -Fq 'sd_pid_get_session' "$source_module"; then
    echo 'Sudo consent must not require a direct logind session for the process.' >&2
    exit 1
fi
if grep -Fq 'HYPRLAND_INSTANCE_SIGNATURE' "$source_module"; then
    echo 'The PAM module must not forward an untrusted Hyprland signature.' >&2
    exit 1
fi

permit_module=/usr/lib/security/pam_permit.so
deny_module=/usr/lib/security/pam_deny.so
[[ -f $permit_module && -f $deny_module ]]

export OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR="$temporary_dir/runtime"
export OMARCHY_FACE_ID_ELEVATION_TEST_TIMEOUT_MS=1000
export OMARCHY_FACE_ID_TEST_SESSION=local
export WAYLAND_DISPLAY=wayland-42
export HYPRLAND_INSTANCE_SIGNATURE=untrusted-and-ignored
export DISPLAY=:99
export XDG_CURRENT_DESKTOP=untrusted-test-value
export XDG_RUNTIME_DIR="$temporary_dir/untrusted-runtime"
mkdir -m 0700 "$OMARCHY_FACE_ID_ELEVATION_RUNTIME_DIR"
: >"$temporary_dir/helper-invocations"
: >"$temporary_dir/helper-environment"

cat >"$temporary_dir/consent-helper" <<EOF
#!/usr/bin/env bash
printf 'request\n' >>'$temporary_dir/helper-invocations'
printf 'PAM_USER=%s\n' "\${PAM_USER-<unset>}" >>'$temporary_dir/helper-environment'
printf 'PAM_RUSER=%s\n' "\${PAM_RUSER-<unset>}" >>'$temporary_dir/helper-environment'
printf 'PAM_SERVICE=%s\n' "\${PAM_SERVICE-<unset>}" >>'$temporary_dir/helper-environment'
printf 'WAYLAND_DISPLAY=%s\n' "\${WAYLAND_DISPLAY-<unset>}" >>'$temporary_dir/helper-environment'
printf 'HYPRLAND_INSTANCE_SIGNATURE=%s\n' "\${HYPRLAND_INSTANCE_SIGNATURE-<unset>}" >>'$temporary_dir/helper-environment'
printf 'DISPLAY=%s\n' "\${DISPLAY-<unset>}" >>'$temporary_dir/helper-environment'
printf 'XDG_CURRENT_DESKTOP=%s\n' "\${XDG_CURRENT_DESKTOP-<unset>}" >>'$temporary_dir/helper-environment'
printf 'XDG_RUNTIME_DIR=%s\n' "\${XDG_RUNTIME_DIR-<unset>}" >>'$temporary_dir/helper-environment'
exec '$bridge' "\$@"
EOF
chmod +x "$temporary_dir/consent-helper"
cat >"$temporary_dir/noisy-verifier" <<'EOF'
#!/usr/bin/env bash
echo 'Please look at the camera'
echo 'Face Verified.' >&2
exit 0
EOF
chmod +x "$temporary_dir/noisy-verifier"

write_included_service() {
    local password_module=$1
    cat >"$temporary_dir/omarchy-face-id" <<EOF
auth [success=done auth_err=die default=ignore] $consent_module helper=$temporary_dir/consent-helper test_mode=1
EOF
    cat >"$temporary_dir/sudo" <<EOF
auth include omarchy-face-id
auth required $password_module
EOF
}

invocation_count() { wc -l <"$temporary_dir/helper-invocations"; }

# Only the verified identity and Wayland candidate cross the PAM boundary. The
# root helper discovers the trusted Hyprland instance itself.
write_included_service "$deny_module"
export OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE=approve
export OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT=success
export OMARCHY_FACE_ID_ELEVATION_TEST_VERIFIER="$temporary_dir/noisy-verifier"
first_output=$("$harness" "$temporary_dir" sudo "$(id -un)" 2>&1)
grep -Fq 'pam_result=0' <<<"$first_output"
if grep -Eq 'Please look at the camera|Face Verified' <<<"$first_output"; then
    echo 'Verifier output escaped into the invoking terminal.' >&2
    exit 1
fi
unset OMARCHY_FACE_ID_ELEVATION_TEST_VERIFIER
grep -Fxq "PAM_USER=$(id -un)" "$temporary_dir/helper-environment"
grep -Fxq 'PAM_RUSER=<unset>' "$temporary_dir/helper-environment"
grep -Fxq 'PAM_SERVICE=<unset>' "$temporary_dir/helper-environment"
grep -Fxq 'WAYLAND_DISPLAY=wayland-42' "$temporary_dir/helper-environment"
grep -Fxq 'HYPRLAND_INSTANCE_SIGNATURE=<unset>' "$temporary_dir/helper-environment"
grep -Fxq 'DISPLAY=<unset>' "$temporary_dir/helper-environment"
grep -Fxq 'XDG_CURRENT_DESKTOP=<unset>' "$temporary_dir/helper-environment"
grep -Fxq 'XDG_RUNTIME_DIR=<unset>' "$temporary_dir/helper-environment"

# A successful face result finishes the include without reaching password.
write_included_service "$deny_module"
"$harness" "$temporary_dir" sudo "$(id -un)"

# Explicit decline cancels the sudo authentication loop after one call and
# opens the overlay only once. It must not become ten failed password attempts.
write_included_service "$permit_module"
export OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE=deny
before=$(invocation_count)
set +e
decline_output=$("$harness" "$temporary_dir" sudo "$(id -un)" 10 2>&1)
decline_status=$?
set -e
if [[ $decline_status -eq 0 ]]; then
    echo 'An explicitly declined request unexpectedly authenticated.' >&2
    exit 1
fi
grep -Fq 'pam_calls=1' <<<"$decline_output"
grep -Fq 'pam_cancelled=1' <<<"$decline_output"
grep -Fq 'pam_conversation_interrupted=1' <<<"$decline_output"
grep -Fq 'sudo_counted_attempts=0' <<<"$decline_output"
[[ $(invocation_count) -eq $((before + 1)) ]]

# Prompt failures reach the unchanged password stack and never respawn the
# overlay in the same PAM transaction.
for behavior in close crash hang malformed; do
    write_included_service "$permit_module"
    export OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE=$behavior
    export OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT=success
    before=$(invocation_count)
    "$harness" "$temporary_dir" sudo "$(id -un)" 3
    [[ $(invocation_count) -eq $((before + 1)) ]]

    write_included_service "$deny_module"
    if "$harness" "$temporary_dir" sudo "$(id -un)"; then
        echo "$behavior bypassed a rejecting password stack." >&2
        exit 1
    fi
done

# A completed biometric failure also falls back once without reopening.
export OMARCHY_FACE_ID_ELEVATION_TEST_RESPONSE=approve
export OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT=failure
write_included_service "$permit_module"
before=$(invocation_count)
"$harness" "$temporary_dir" sudo "$(id -un)" 3
[[ $(invocation_count) -eq $((before + 1)) ]]
write_included_service "$deny_module"
if "$harness" "$temporary_dir" sudo "$(id -un)"; then
    echo 'A failed face and rejecting password unexpectedly authenticated.' >&2
    exit 1
fi

# Manager-launched local terminals remain valid.
export OMARCHY_FACE_ID_TEST_SESSION=manager-local
export OMARCHY_FACE_ID_ELEVATION_TEST_VERIFY_RESULT=success
write_included_service "$deny_module"
before=$(invocation_count)
"$harness" "$temporary_dir" sudo "$(id -un)"
[[ $(invocation_count) -eq $((before + 1)) ]]

# Remote, headless, and inactive sessions never launch the visual helper.
for session in ssh headless inactive; do
    export OMARCHY_FACE_ID_TEST_SESSION=$session
    write_included_service "$permit_module"
    before=$(invocation_count)
    "$harness" "$temporary_dir" sudo "$(id -un)"
    [[ $(invocation_count) -eq $before ]]

    write_included_service "$deny_module"
    if "$harness" "$temporary_dir" sudo "$(id -un)"; then
        echo "$session session bypassed a rejecting password stack." >&2
        exit 1
    fi
    [[ $(invocation_count) -eq $before ]]
done

# No PAM service other than sudo may launch the coordinator.
export OMARCHY_FACE_ID_TEST_SESSION=local
cp "$temporary_dir/sudo" "$temporary_dir/not-sudo"
before=$(invocation_count)
if "$harness" "$temporary_dir" not-sudo "$(id -un)"; then
    echo 'A non-sudo PAM service bypassed its rejecting password stack.' >&2
    exit 1
fi
[[ $(invocation_count) -eq $before ]]
