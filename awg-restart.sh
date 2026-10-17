#!/usr/bin/env bash
# NetworkManager dispatcher: when an uplink comes up, restart the AmneziaWG tunnels that are
# already up. TUNNELS lists them, or RULE names an opensnitch rule whose iface.out regex does.
set -euo pipefail
. /usr/local/lib/watchdog.sh

TUNNELS=()
RULE=""
LOG="/var/log/awg-restart.log"
MAX_ATTEMPTS=5
CHECK_HOST="8.8.8.8"
load_config awg-restart

log() { echo "[$(date '+%F %T')] $*" >> "${LOG}"; }

tunnels() {
    jq -r '.operator.list[] | select(.operand == "iface.out") | .data' "${RULE}" \
        | sed -E 's/^\^\(//; s/\)\$$//' | tr '|' '\n' | sed '/^lo$/d'
}

# On success ATTEMPTS holds the number of tries used.
restart() {
    local tun="$1"
    for (( ATTEMPTS = 1; ATTEMPTS <= MAX_ATTEMPTS; ATTEMPTS++ )); do
        log "${tun}: attempt ${ATTEMPTS}/${MAX_ATTEMPTS}"
        awg-quick down "${tun}" >> "${LOG}" 2>&1 || true
        awg-quick up "${tun}" >> "${LOG}" 2>&1 || { log "${tun}: up failed"; continue; }
        sleep 2
        if ping -c2 -W3 -I "${tun}" "${CHECK_HOST}" &> /dev/null; then
            log "${tun}: connected"
            return 0
        fi
        log "${tun}: no connectivity, retrying"
    done
    log "${tun}: no connectivity after ${MAX_ATTEMPTS} attempts"
    return 1
}

[[ "${2:-}" == "up" ]] || exit 0

[[ -n "${RULE}" ]] && mapfile -t TUNNELS < <(tunnels)
(( ${#TUNNELS[@]} )) || exit 0
printf '%s\n' "${TUNNELS[@]}" | grep -qxF -- "${1:-}" && exit 0
[[ -n "$(ip route show default dev "${1:-}" 2>/dev/null)" ]] || exit 0

failed=()
for tun in "${TUNNELS[@]}"; do
    awg show "${tun}" &> /dev/null || continue
    ping -c2 -W3 -I "${tun}" "${CHECK_HOST}" &> /dev/null && continue
    log "NM event: ${1} ${2}, restarting ${tun}"
    if restart "${tun}"; then
        notify normal "AmneziaWG: ${tun} restored" "${ATTEMPTS}/${MAX_ATTEMPTS} attempts"
    else
        failed+=("${tun}")
    fi
done

(( ${#failed[@]} )) || exit 0
rate_limited awg-restart 300 && exit 1

notify critical "AmneziaWG: ${failed[*]} down" "${MAX_ATTEMPTS} attempts failed"
exit 1
