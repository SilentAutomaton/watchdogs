#!/usr/bin/env bash
# Alert when any filesystem exceeds THRESHOLD% usage.
set -euo pipefail

THRESHOLD=90
MAILBOX="/var/mail/silent"
WATCH_MOUNTS=("/" "/home")

notify() {
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}" \
        notify-send -u critical -a watchdog "${1}" "${2:-}" 2>/dev/null || true
}

alerts=$(df -h --output=pcent,target,source "${WATCH_MOUNTS[@]}" | awk -v t="${THRESHOLD}" 'NR>1 {
    pct=$1; sub(/%/,"",pct)
    if (pct+0 >= t) print $0
}')

[[ -z "${alerts}" ]] && exit 0

subject=$(echo "${alerts}" | awk '{printf "%s %s; ", $2, $1}' | sed 's/; $//')

{
    printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
    printf 'From: watchdog@localhost\n'
    printf 'To: silent\n'
    printf 'Subject: [watchdog] disk: %s\n' "${subject}"
    printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
    printf '\n'
    printf 'Time: %s\n\n' "$(date -R)"
    printf 'Filesystems over %s%%:\n\n' "${THRESHOLD}"
    printf '%s\n\n' "${alerts}"
    df -h "${WATCH_MOUNTS[@]}"
    printf '\n'
} >> "${MAILBOX}"

notify "Disk: ${subject}" ""
