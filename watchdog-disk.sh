#!/usr/bin/env bash
# Alert when any filesystem exceeds THRESHOLD% usage.
set -euo pipefail
. /usr/local/lib/watchdog.sh

THRESHOLD=90
WATCH_MOUNTS=("/" "/home")

alerts=$(df -h --output=pcent,target,source "${WATCH_MOUNTS[@]}" | awk -v t="${THRESHOLD}" 'NR>1 {
    pct=$1; sub(/%/,"",pct)
    if (pct+0 >= t) print $0
}')

[[ -z "${alerts}" ]] && exit 0

subject=$(echo "${alerts}" | awk '{printf "%s %s; ", $2, $1}' | sed 's/; $//')

{
    printf 'Time: %s\n\n' "$(date -R)"
    printf 'Filesystems over %s%%:\n\n' "${THRESHOLD}"
    printf '%s\n\n' "${alerts}"
    df -h "${WATCH_MOUNTS[@]}"
} | send_mail "[watchdog] disk: ${subject}"

notify critical "Disk: ${subject}" ""
