#!/usr/bin/env bash
# Alert when a filesystem crosses THRESHOLD% usage, then again only per STEP% of growth.
set -euo pipefail
. /usr/local/lib/watchdog.sh

THRESHOLD=90
STEP=2
WATCH_MOUNTS=("/")
load_config disk
STATE_DIR="${STATE_DIRECTORY:-/var/lib/watchdog-disk}"

alerts=()
for mnt in "${WATCH_MOUNTS[@]}"; do
    pct=$(df --output=pcent "${mnt}" | awk 'NR == 2 {print $1 + 0}')
    state="${STATE_DIR}/${mnt//\//_}"
    if (( pct < THRESHOLD )); then
        rm -f "${state}"
        continue
    fi
    last=$(cat "${state}" 2>/dev/null || echo 0)
    (( pct < last + STEP )) && continue
    echo "${pct}" > "${state}"
    alerts+=("${mnt} ${pct}%")
done

(( ${#alerts[@]} )) || exit 0

subject=$(printf '%s; ' "${alerts[@]}")
subject="${subject%; }"

{
    printf 'Time: %s\n\n' "$(date -R)"
    printf 'Over %s%%, next alert after %s%% more:\n\n' "${THRESHOLD}" "${STEP}"
    printf '%s\n' "${alerts[@]}"
    printf '\n'
    df -h "${WATCH_MOUNTS[@]}"
} | send_mail "[watchdog] disk: ${subject}"

notify critical "Disk: ${subject}" ""
