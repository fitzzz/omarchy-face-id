#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$project_root/scripts/uninstall.sh"

bash -n "$script"
grep -Fq 'gaze remove-face "$face_name" --user "$account_name"' "$script"
grep -Fq 'omarchy plugin remove "$plugin_id" --yes' "$script"
grep -Fq '"$expected_gaze_receipt") gaze_ownership=legacy' "$script"
grep -Fq '"$expected_gaze_aur_receipt") gaze_ownership=aur' "$script"
grep -Fq 'sudo pacman -Rns --noconfirm gaze' "$script"
grep -Fq 'gaze uninstall --yes' "$script"
grep -Fq 'Your password will not change.' "$script"

owned_line=$(grep -n 'if ((gaze_owned)); then' "$script" | tail -1 | cut -d: -f1)
package_line=$(grep -n 'sudo pacman -Rns --noconfirm gaze' "$script" | cut -d: -f1)
[[ $package_line -gt $owned_line ]]

if rg -q 'gaze clear-user' "$script"; then
    echo "The uninstaller must remove only this app's named face from shared Gaze installs." >&2
    exit 1
fi

grep -Fq 'recordEnrollmentOwnership(m_enrollmentFaceName)' \
    "$project_root/app/GazeClient.cpp"

run_case() {
    local mode=$1
    local sandbox="$temporary_dir/$mode"
    install -d "$sandbox/bin" "$sandbox/plugin" "$sandbox/state/omarchy-face-id" \
        "$sandbox/ownership"
    printf '%s\n' '{"id": "fitzzz.face-id"}' >"$sandbox/plugin/manifest.json"
    printf '%s\n' '# Face-only service for Omarchy Face ID.' >"$sandbox/pam"
    printf '%s\n' default >"$sandbox/state/omarchy-face-id/enrolled-face"

    cat >"$sandbox/bin/gaze" <<'EOF'
#!/usr/bin/env bash
printf 'gaze %s\n' "$*" >>"$TEST_LOG"
if [[ $1 == list-faces ]]; then
    printf '  • default [RGB] (5 captures)\n'
fi
EOF
    cat >"$sandbox/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >>"$TEST_LOG"
EOF
    cat >"$sandbox/bin/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman %s\n' "$*" >>"$TEST_LOG"
[[ $1 == -Q && $2 == gaze ]]
EOF
    cat >"$sandbox/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
EOF
    chmod +x "$sandbox/bin/"*

    if [[ $mode == owned ]]; then
        printf '%s\n' 'omarchy-face-id:gaze:0.2.12-1' \
            >"$sandbox/ownership/gaze-installed"
    elif [[ $mode == aur_owned ]]; then
        printf '%s\n' 'omarchy-face-id:gaze-aur:gaze-bin' \
            >"$sandbox/ownership/gaze-installed"
    fi

    TEST_LOG="$sandbox/actions.log" \
    PATH="$sandbox/bin:/usr/bin" \
    XDG_STATE_HOME="$sandbox/state" \
    OMARCHY_FACE_ID_PLUGIN_TARGET="$sandbox/plugin" \
    OMARCHY_FACE_ID_PAM_PATH="$sandbox/pam" \
    OMARCHY_FACE_ID_OWNERSHIP_DIR="$sandbox/ownership" \
    OMARCHY_FACE_ID_SKIP_LOCK_CHECK=1 \
        "$script" --yes >"$sandbox/output.log"
}

temporary_dir=$(mktemp -d -t omarchy-face-id-uninstall-test.XXXXXX)
trap 'rm -rf -- "$temporary_dir"' EXIT

run_case preexisting
grep -Fq 'gaze remove-face default --user' "$temporary_dir/preexisting/actions.log"
if grep -Eq 'sudo (systemctl|pacman|rm)' "$temporary_dir/preexisting/actions.log"; then
    echo "A pre-existing Gaze installation would be removed." >&2
    exit 1
fi
grep -Fq 'Gaze was already present before Face ID setup, so it was kept.' \
    "$temporary_dir/preexisting/output.log"

run_case owned
grep -Fq 'sudo systemctl disable --now gazed.service' \
    "$temporary_dir/owned/actions.log"
grep -Fq 'sudo pacman -Rns --noconfirm gaze' "$temporary_dir/owned/actions.log"
grep -Fq 'sudo rm -rf -- /etc/gaze /var/cache/gaze /var/lib/gaze' \
    "$temporary_dir/owned/actions.log"

run_case aur_owned
grep -Fq 'gaze uninstall --yes' "$temporary_dir/aur_owned/actions.log"
