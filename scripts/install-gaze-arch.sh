#!/usr/bin/env bash

set -euo pipefail

gaze_version="0.2.12"
package_name="gaze-${gaze_version}-1-x86_64.pkg.tar.zst"
package_url="https://github.com/GunduLabs/gaze/releases/download/v${gaze_version}/${package_name}"
package_sha256="72312d159ae422d70f50954e994b78484f76104de16249b97a095d5bd1e2e7a5"

if [[ ${EUID} -eq 0 ]]; then
    echo "Run this script as your normal user; it will request sudo only for package and service operations." >&2
    exit 1
fi

for command_name in curl pacman sha256sum sudo systemctl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $command_name" >&2
        exit 1
    fi
done

temporary_dir=$(mktemp -d -t omarchy-face-id-gaze.XXXXXX)
package_path="$temporary_dir/$package_name"
before_snapshot="$temporary_dir/pam-before"
after_snapshot="$temporary_dir/pam-after"

cleanup() {
    rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

snapshot_password_path() {
    local candidate
    for candidate in \
        /etc/pam.d/sudo \
        /etc/pam.d/polkit-1 \
        /etc/pam.d/omarchy-lock-password \
        /etc/pam.d/system-auth; do
        if [[ -f "$candidate" ]]; then
            sha256sum "$candidate"
        else
            printf 'missing  %s\n' "$candidate"
        fi
    done
}

snapshot_password_path >"$before_snapshot"

echo "Downloading verified Gaze ${gaze_version} package…"
curl --fail --location --show-error "$package_url" --output "$package_path"
printf '%s  %s\n' "$package_sha256" "$package_path" | sha256sum --check --status

echo "Installing Gaze without running its PAM-changing package scriptlet…"
sudo pacman -U --noscriptlet --needed --noconfirm "$package_path"

snapshot_password_path >"$after_snapshot"
if ! cmp --silent "$before_snapshot" "$after_snapshot"; then
    echo "A protected PAM file changed unexpectedly. Review the following difference before continuing:" >&2
    diff --unified "$before_snapshot" "$after_snapshot" >&2 || true
    exit 1
fi

sudo systemctl enable --now gazed.service

echo
echo "Gaze ${gaze_version} is installed and gazed.service is running."
echo "Protected password, sudo, and polkit PAM files were unchanged."
echo "Run 'gaze doctor' for diagnostics, then use Omarchy Face ID to enroll."
