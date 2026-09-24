#!/usr/bin/env bash
# Detects new listening ports by diffing ss output against saved state.
# Runs as root: without it ss hides the process of root sockets.
set -euo pipefail

STATE_FILE="/run/watchdog-ports/state"
MAILBOX="/var/mail/silent"

notify() {
    runuser -u silent -- env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
        notify-send -u normal -a watchdog "${1}" "${2:-}" 2>/dev/null || true
}

listeners=$(ss -tulpnH 2>/dev/null)
# UDP sockets on ephemeral ports are clients (DNS, WebRTC, VPN), not listeners.
read -r eph_lo eph_hi < /proc/sys/net/ipv4/ip_local_port_range
current=$(awk -v lo="${eph_lo}" -v hi="${eph_hi}" '{
    port = $5; sub(/.*:/, "", port)
    if ($1 == "udp" && port + 0 >= lo && port + 0 <= hi) next
    print $1, $5
}' <<< "${listeners}" | sort -u)

if [[ ! -f "${STATE_FILE}" ]]; then
    echo "${current}" > "${STATE_FILE}"
    exit 0
fi

prev=$(< "${STATE_FILE}")
new_ports=$(comm -13 <(echo "${prev}") <(echo "${current}") || true)
echo "${current}" > "${STATE_FILE}"

[[ -z "${new_ports}" ]] && exit 0

# "users:(("cupsd",pid=812,fd=7))" -> "cupsd"
owner_of() {
    awk -v p="$1" -v a="$2" '$1 == p && $5 == a {print $7}' <<< "${listeners}" \
        | grep -oP 'users:\(\("\K[^"]+' | sort -u | paste -sd, || true
}

summary=""
details=""
while read -r proto addr; do
    proc=$(owner_of "${proto}" "${addr}")
    summary+="${addr} (${proc:-?}) "
    details+=$(awk -v p="${proto}" -v a="${addr}" '$1 == p && $5 == a' <<< "${listeners}")$'\n'
done <<< "${new_ports}"
summary="${summary% }"

{
    printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
    printf 'From: watchdog@localhost\n'
    printf 'To: silent\n'
    printf 'Subject: [watchdog] new listener(s): %s\n' "${summary}"
    printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
    printf '\n'
    printf 'Time: %s\n\n' "$(date -R)"
    printf 'New:\n%s\n' "${details}"
    printf 'All current listeners:\n\n'
    ss -tulpn
    printf '\n'
} | runuser -u silent -- tee -a "${MAILBOX}" >/dev/null  # fs.protected_regular denies root here

notify "New port(s) listening" "${summary}"
