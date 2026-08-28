#!/usr/bin/env bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$project_dir/scripts/install-gaze-arch.sh"

bash -n "$script"
grep -Fq 'pacman -U --noscriptlet' "$script"
grep -Fq '72312d159ae422d70f50954e994b78484f76104de16249b97a095d5bd1e2e7a5' "$script"
grep -Fq 'snapshot_password_path >"$before_snapshot"' "$script"
grep -Fq 'snapshot_password_path >"$after_snapshot"' "$script"
grep -Fq 'pacman -Q gaze' "$script"
grep -Fq 'ownership_receipt="$ownership_dir/gaze-installed"' "$script"
grep -Fq 'Omarchy Face ID will use it but will never remove it' "$script"

if rg -q '(install|cp|mv|tee).*pam\.d' "$script"; then
    echo "The Gaze installer must not write a PAM configuration." >&2
    exit 1
fi
