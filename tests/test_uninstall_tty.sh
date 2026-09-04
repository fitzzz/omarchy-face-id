#!/usr/bin/env bash

set -euo pipefail

app_binary=${1:?app binary is required}
uninstaller=${2:?uninstaller script is required}
temporary_dir=$(mktemp -d -t omarchy-face-id-uninstall-tty.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

install -d "$temporary_dir/bin" "$temporary_dir/pam.d" \
    "$temporary_dir/libexec" "$temporary_dir/security" "$temporary_dir/verify-pam"
printf '%s\n' '#%PAM-1.0' 'auth include system-auth' \
    >"$temporary_dir/pam.d/sudo"
for command_name in sudo pacman omarchy; do
    printf '%s\n' '#!/usr/bin/env bash' 'exit 99' \
        >"$temporary_dir/bin/$command_name"
    chmod +x "$temporary_dir/bin/$command_name"
done

app_command=$(printf '%q' "$app_binary")
output=$(printf 'n\n' | \
    XDG_STATE_HOME="$temporary_dir/state" \
    PATH="$temporary_dir/bin:/usr/bin" \
    OMARCHY_FACE_ID_TEST_ROOT="$temporary_dir" \
    OMARCHY_FACE_ID_UNINSTALLER_PATH="$uninstaller" \
    OMARCHY_FACE_ID_UNINSTALLER_TEST_MODE=1 \
    OMARCHY_FACE_ID_PLUGIN_TARGET="$temporary_dir/plugin" \
    OMARCHY_FACE_ID_PAM_PATH="$temporary_dir/pam.d/omarchy-face-id-lock" \
    OMARCHY_FACE_ID_OWNERSHIP_DIR="$temporary_dir/ownership" \
    OMARCHY_FACE_ID_SUDO_PAM_PATH="$temporary_dir/pam.d/sudo" \
    OMARCHY_FACE_ID_SUDO_FACE_PAM_PATH="$temporary_dir/pam.d/omarchy-face-id" \
    OMARCHY_FACE_ID_POLKIT_PAM_PATH="$temporary_dir/pam.d/polkit-1" \
    OMARCHY_FACE_ID_ELEVATION_TARGET="$temporary_dir/libexec/elevation" \
    OMARCHY_FACE_ID_CONSENT_TARGET="$temporary_dir/security/consent.so" \
    OMARCHY_FACE_ID_VERIFY_PAM_DIR="$temporary_dir/verify-pam" \
    OMARCHY_FACE_ID_SKIP_LOCK_CHECK=1 \
    script --quiet --return --command "$app_command --uninstall" /dev/null)

grep -Fq 'Continue? [y/N]' <<<"$output"
if grep -Fq 'Run interactively or pass --yes.' <<<"$output"; then
    echo "The AppImage wrapper did not forward its terminal input." >&2
    exit 1
fi
