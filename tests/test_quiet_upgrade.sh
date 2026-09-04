#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
temporary_dir=$(mktemp -d -t face-id-quiet-upgrade.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

[[ $temporary_dir == /tmp/face-id-quiet-upgrade.* ]]
[[ $app_binary != /usr/* && $app_binary != /bin/* && $app_binary != /sbin/* ]]

install -d "$temporary_dir/bin" "$temporary_dir/config" \
    "$temporary_dir/state/omarchy-face-id" "$temporary_dir/ownership/users" \
    "$temporary_dir/theme/theme"
install -m 0755 "$project_root/tests/fixtures/activation-plugin-enable" \
    "$temporary_dir/bin/omarchy-plugin-enable"
install -m 0755 "$project_root/tests/fixtures/omarchy-shell" \
    "$temporary_dir/bin/omarchy-shell"
install -m 0755 "$project_root/tests/fixtures/omarchy-shell" \
    "$temporary_dir/bin/omarchy-restart-shell"

printf '%s\n' 'test elevation helper' >"$temporary_dir/elevation"
chmod +x "$temporary_dir/elevation"
printf '%s\n' 'test consent module' >"$temporary_dir/consent.so"
printf '%s\n' 'omarchy-face-id:registered-user:1' \
    >"$temporary_dir/ownership/users/$(id -u)"
printf '%s\n' \
    '# BEGIN Omarchy Face ID sudo' \
    'auth include omarchy-face-id' \
    '# END Omarchy Face ID sudo' >"$temporary_dir/sudo-pam"
printf '%s\n' \
    '# Omarchy Face ID sudo authentication. Managed by Omarchy Face ID.' \
    "auth [success=done auth_err=die default=ignore] pam_omarchy_face_id_consent.so helper=$temporary_dir/elevation" \
    >"$temporary_dir/face-pam"
printf '%s\n' \
    '# Omarchy Face ID private face verification. Managed by Omarchy Face ID.' \
    'auth [success=done ignore=ignore default=bad] pam_gaze.so' \
    'auth required pam_deny.so' \
    'account required pam_permit.so' \
    >"$temporary_dir/verifier-pam"
: >"$temporary_dir/polkit-pam"
cp "$project_root/packaging/pam/omarchy-face-id-lock" \
    "$temporary_dir/lock-pam"
printf '%s\n' default >"$temporary_dir/state/omarchy-face-id/enrolled-face"
printf '%s\n' 'accent = "#509475"' >"$temporary_dir/theme/theme/colors.toml"

run_quiet_upgrade() {
    local state_home=$1
    PATH="$temporary_dir/bin:$PATH" \
    XDG_STATE_HOME="$state_home" \
    GSETTINGS_BACKEND=memory \
    OMARCHY_FACE_ID_CONFIG_ROOT="$temporary_dir/config" \
    OMARCHY_FACE_ID_PAM_PATH="$temporary_dir/lock-pam" \
    OMARCHY_FACE_ID_OWNERSHIP_DIR="$temporary_dir/ownership" \
    OMARCHY_FACE_ID_SUDO_PAM_PATH="$temporary_dir/sudo-pam" \
    OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH="$temporary_dir/face-pam" \
    OMARCHY_FACE_ID_VERIFY_PAM_PATH="$temporary_dir/verifier-pam" \
    OMARCHY_FACE_ID_POLKIT_PAM_PATH="$temporary_dir/polkit-pam" \
    OMARCHY_FACE_ID_ELEVATION_HELPER_PATH="$temporary_dir/elevation" \
    OMARCHY_FACE_ID_ELEVATION_TARGET="$temporary_dir/elevation" \
    OMARCHY_FACE_ID_CONSENT_MODULE_PATH="$temporary_dir/consent.so" \
    OMARCHY_FACE_ID_CONSENT_TARGET="$temporary_dir/consent.so" \
    OMARCHY_FACE_ID_THEME_ROOT="$temporary_dir/theme" \
    OMARCHY_FACE_ID_ACTIVATION_TIMEOUT_MS=2500 \
    OMARCHY_FACE_ID_COMMAND_TIMEOUT_MS=200 \
    OMARCHY_FACE_ID_VERIFY_TIMEOUT_MS=200 \
    OMARCHY_FACE_ID_TEST_MODE=success \
        "$app_binary" --upgrade-quietly
}

output=$(run_quiet_upgrade "$temporary_dir/state" 2>&1)
candidate_version=$($app_binary --version | awk '{print $NF}')
grep -Fq "Quietly upgrading Face ID to $candidate_version…" <<<"$output"
grep -Fq 'Updating the Omarchy Face ID integration…' <<<"$output"
grep -Fq "Face ID upgraded to $candidate_version." <<<"$output"
if grep -Fq 'Omarchy theme loaded:' <<<"$output"; then
    echo 'Quiet upgrades must not print internal theme reloads.' >&2
    exit 1
fi
grep -Fxq "$candidate_version" \
    "$temporary_dir/config/omarchy/plugins/fitzzz.face-id/.omarchy-face-id-version"

# This command upgrades an existing enrolled installation; it must never turn
# into a silent first-run installer that captures or invents a face.
rm -rf -- "$temporary_dir/config/omarchy/plugins"
set +e
missing_output=$(run_quiet_upgrade "$temporary_dir/missing-state" 2>&1)
missing_status=$?
set -e
[[ $missing_status -eq 2 ]]
grep -Fq 'only available after Face ID has been set up' <<<"$missing_output"
