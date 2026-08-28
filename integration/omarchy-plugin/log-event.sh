#!/usr/bin/env bash

set -euo pipefail
umask 077

event=${1:-}
level=${2:-}
session_id=${3:-}
shift 3 || true

[[ $event =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$ ]] || exit 2
[[ $level =~ ^(debug|info|warning|error)$ ]] || exit 2
[[ $session_id =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || exit 2

state_root=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir="$state_root/omarchy-face-id"
log_file="$state_dir/diagnostics.jsonl"
mkdir -p "$state_dir"
chmod 700 "$state_dir"

exec 9>"$state_dir/diagnostics.lock"
flock -x 9

sequence=0
[[ -s $state_dir/lock-sequence ]] && sequence=$(<"$state_dir/lock-sequence")
sequence=$((sequence + 1))
printf '%s\n' "$sequence" >"$state_dir/lock-sequence"

attributes='{}'
for pair in "$@"; do
    [[ $pair == *=* ]] || continue
    key=${pair%%=*}
    value=${pair#*=}
    [[ $key =~ ^[a-z][a-z0-9_]{0,47}$ ]] || continue
    [[ $key =~ (^|_)(user|username|name|path|device|command|output|message|frame|image|jpeg|embedding|biometric|token|password|secret|email|hostname|address|ip)($|_) ]] && continue

    if [[ $key == *_id && $value =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$ ]]; then
        attributes=$(/usr/bin/jq -cn --argjson current "$attributes" \
            --arg key "$key" --arg value "$value" '$current + {($key): $value}')
    elif [[ $value =~ ^-?[0-9]+([.][0-9]+)?$ || $value =~ ^(true|false|null)$ ]]; then
        attributes=$(/usr/bin/jq -cn --argjson current "$attributes" \
            --arg key "$key" --argjson value "$value" '$current + {($key): $value}')
    elif [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{0,79}$ ]]; then
        attributes=$(/usr/bin/jq -cn --argjson current "$attributes" \
            --arg key "$key" --arg value "$value" '$current + {($key): $value}')
    fi
done

if [[ -f $log_file ]] && (( $(stat -c '%s' "$log_file") >= 1048576 )); then
    rm -f -- "$log_file.3"
    [[ ! -f $log_file.2 ]] || mv -- "$log_file.2" "$log_file.3"
    [[ ! -f $log_file.1 ]] || mv -- "$log_file.1" "$log_file.2"
    mv -- "$log_file" "$log_file.1"
fi

component='lock.authentication'
[[ $event != camera_* ]] || component='camera.inventory'
record=$(/usr/bin/jq -cn \
    --arg schema 'omarchy.face-id.diagnostics.event' \
    --arg timestamp "$(date -u +'%Y-%m-%dT%H:%M:%S.%3NZ')" \
    --arg session "$session_id" \
    --arg level "$level" \
    --arg component "$component" \
    --arg event "$event" \
    --argjson sequence "$sequence" \
    --argjson attributes "$attributes" \
    '{schema:$schema,schema_version:1,timestamp_utc:$timestamp,session_id:$session,sequence:$sequence,level:$level,component:$component,event:$event,attributes:$attributes}')
printf '%s\n' "$record" >>"$log_file"
chmod 600 "$log_file" "$state_dir/lock-sequence"

if [[ $event == attempt_started ]]; then
    flock -u 9

    read_camera_setting() {
        local key=$1
        awk -v wanted="$key" '
            /^\[cameras\]/ { in_cameras=1; next }
            /^\[/ { in_cameras=0 }
            in_cameras && $0 ~ "^[[:space:]]*" wanted "[[:space:]]*=" {
                value=$0
                sub(/^[^=]*=[[:space:]]*/, "", value)
                sub(/^"/, "", value)
                sub(/"[[:space:]]*(#.*)?$/, "", value)
                print value
                exit
            }
        ' /etc/gaze/config.toml 2>/dev/null || true
    }

    selection_mode() {
        case $1 in
            "") printf none ;;
            primary) printf primary ;;
            pipewiresrc*) printf pipewire ;;
            /dev/video*) printf v4l2 ;;
            usb:*) printf usb ;;
            *) printf custom ;;
        esac
    }

    rgb_selection=$(read_camera_setting rgb)
    ir_selection=$(read_camera_setting ir)
    shopt -s nullglob
    camera_nodes=(/sys/class/video4linux/video*)
    rgb_resolved=false
    ir_resolved=false

    for index in "${!camera_nodes[@]}"; do
        node=${camera_nodes[$index]}
        node_name=${node##*/}
        canonical=$(readlink -f "$node" 2>/dev/null || true)
        vendor=unknown
        product=unknown
        cursor=$canonical
        for _ in {1..8}; do
            [[ ! -f $cursor/idVendor ]] || vendor=$(tr '[:upper:]' '[:lower:]' <"$cursor/idVendor")
            [[ ! -f $cursor/idProduct ]] || product=$(tr '[:upper:]' '[:lower:]' <"$cursor/idProduct")
            [[ $vendor == unknown || $product == unknown ]] || break
            cursor=${cursor%/*}
            [[ -n $cursor ]] || break
        done
        [[ $vendor =~ ^[0-9a-f]{4}$ ]] || vendor=unknown
        [[ $product =~ ^[0-9a-f]{4}$ ]] || product=unknown

        transport=platform
        if [[ $canonical == *'/virtual/'* ]]; then
            transport=virtual
        elif [[ $canonical == *'/usb'* ]]; then
            transport=usb
        elif [[ $canonical == *'/pci'* ]]; then
            transport=pci
        fi

        configured_rgb=false
        configured_ir=false
        if [[ $rgb_selection == "/dev/$node_name" \
            || $rgb_selection == "usb:$vendor:$product" ]]; then
            configured_rgb=true
            rgb_resolved=true
        fi
        if [[ $ir_selection == "/dev/$node_name" \
            || $ir_selection == "usb:$vendor:$product" ]]; then
            configured_ir=true
            ir_resolved=true
        fi

        "$0" camera_node_observed debug "$session_id" \
            trigger=lock_attempt camera_slot="$index" transport="$transport" \
            vendor_id="$vendor" product_id="$product" \
            configured_rgb="$configured_rgb" configured_ir="$configured_ir"
    done

    "$0" camera_selection_observed info "$session_id" \
        trigger=lock_attempt node_count="${#camera_nodes[@]}" \
        rgb_mode="$(selection_mode "$rgb_selection")" \
        ir_mode="$(selection_mode "$ir_selection")" \
        rgb_resolved="$rgb_resolved" ir_resolved="$ir_resolved"
fi
