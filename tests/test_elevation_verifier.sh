#!/usr/bin/env bash

set -euo pipefail

bridge=${1:?elevation helper is required}
temporary_dir=$(mktemp -d -t face-id-verifier.XXXXXX)
cleanup() { rm -rf -- "$temporary_dir"; }
trap cleanup EXIT

[[ $temporary_dir == /tmp/face-id-verifier.* ]]
[[ $bridge != /usr/* && $bridge != /bin/* && $bridge != /sbin/* ]]

pam_dir="$temporary_dir/pam.d"
mkdir -m 0755 "$pam_dir"
export OMARCHY_FACE_ID_ELEVATION_ALLOW_UNPRIVILEGED=1
export OMARCHY_FACE_ID_ELEVATION_TEST_PAM_DIR="$pam_dir"
export PAM_USER
PAM_USER=$(id -un)

run_verify() {
    local expected=$1
    local output="$temporary_dir/output"
    set +e
    setsid "$bridge" verify >"$output" 2>&1
    local status=$?
    set -e
    [[ $status -eq $expected ]] || {
        printf 'verifier returned %s, expected %s\n' "$status" "$expected" >&2
        sed -n '1,120p' "$output" >&2
        exit 1
    }
    [[ ! -s $output ]] || {
        echo 'The private verifier wrote to its terminal streams.' >&2
        sed -n '1,120p' "$output" >&2
        exit 1
    }
}

cat >"$pam_dir/sudo" <<'EOF'
auth [success=done ignore=ignore default=bad] pam_permit.so
auth required pam_deny.so
account required pam_permit.so
EOF
chmod 0644 "$pam_dir/sudo"
run_verify 0

cat >"$pam_dir/sudo" <<'EOF'
auth [success=done ignore=ignore default=bad] pam_deny.so
auth required pam_deny.so
account required pam_permit.so
EOF
run_verify 20

printf 'message that must stay private\n' >"$temporary_dir/message"
cat >"$pam_dir/sudo" <<EOF
auth optional pam_echo.so file=$temporary_dir/message
auth [success=done ignore=ignore default=bad] pam_permit.so
account required pam_permit.so
EOF
run_verify 0

cat >"$pam_dir/sudo" <<'EOF'
auth [success=done ignore=ignore default=bad] pam_module_that_does_not_exist.so
auth required pam_deny.so
account required pam_permit.so
EOF
run_verify 20

chmod 0666 "$pam_dir/sudo"
run_verify 20
chmod 0644 "$pam_dir/sudo"
chmod 0777 "$pam_dir"
run_verify 20
chmod 0755 "$pam_dir"
mv "$pam_dir/sudo" "$pam_dir/not-sudo"
run_verify 20
