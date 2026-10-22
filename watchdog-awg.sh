#!/usr/bin/env bash
# Restart AmneziaWG tunnels whose data path is dead. TSPU freezes UDP flows: the handshake stays
# fresh, no data passes, and only a new source port heals it. Runs every 10 s from a timer.
set -euo pipefail
. "${WATCHDOG_LIB:-/usr/local/lib/watchdog.sh}"

TUNNELS=()
RULE=""
CHECK_HOST="8.8.8.8"
AWG_UNIT=""
BACKOFF=30
MAX_BACKOFF=300
ALERT_AFTER=3
STATE_DIR="/run/watchdog-awg"
load_config awg-watchdog

healthy() { ping -c2 -W2 -I "$1" "${CHECK_HOST}" &> /dev/null; }

alert() {
    rate_limited "awg-watchdog-${1}" 1800 && return 0
    notify critical "AmneziaWG: ${1} down" "${2} restarts did not help"
    printf '%s passes no data after %s restarts.\n' "${1}" "${2}" \
        | send_mail "AmneziaWG: ${1} down" || true
}

# The state file holds "<next restart time> <next backoff> <failed restarts>".
heal() {
    local tun="$1" state="${STATE_DIR}/${1}" now next=0 backoff="${BACKOFF}" failures=0
    now=$(date +%s)
    [[ -r "${state}" ]] && read -r next backoff failures < "${state}"
    if (( now < next )); then
        echo "${tun}: data path down, next restart in $(( next - now )) s"
        return 0
    fi

    echo "${tun}: data path down, restarting for a new source port"
    awg_restart_tunnel "${tun}" "${AWG_UNIT}" || echo "${tun}: restart failed"
    sleep 3
    if healthy "${tun}"; then
        echo "${tun}: restored"
        notify normal "AmneziaWG: ${tun} restored" "restarted for a new source port"
        rm -f "${state}"
        return 0
    fi

    failures=$(( failures + 1 ))
    echo "${tun}: still down after ${failures} restarts, next try in ${backoff} s"
    echo "$(( now + backoff )) $(( backoff * 2 < MAX_BACKOFF ? backoff * 2 : MAX_BACKOFF )) ${failures}" > "${state}"
    (( failures < ALERT_AFTER )) || alert "${tun}" "${failures}"
}

install -d -m 700 "${STATE_DIR}"
mapfile -t tunnels < <(awg_tunnels "${RULE}" "${TUNNELS[@]}")
for tun in "${tunnels[@]}"; do
    awg show "${tun}" &> /dev/null || continue
    if healthy "${tun}"; then
        rm -f "${STATE_DIR:?}/${tun}"
    else
        heal "${tun}"
    fi
done
