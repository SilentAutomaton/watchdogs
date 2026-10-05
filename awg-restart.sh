#!/usr/bin/env bash
# NetworkManager dispatcher: when a network comes up, restart the AmneziaWG tunnels that are
# already up. The tunnels are the interfaces the vpnonly killswitch lets through.
set -euo pipefail
. /usr/local/lib/watchdog.sh

RULE="/etc/opensnitchd/rules/000-vpnonly-allow-claude.json"
LOG="/var/log/awg-restart.log"
MAX_ATTEMPTS=5
CHECK_HOST="8.8.8.8"

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

mapfile -t TUNNELS < <(tunnels)
printf '%s\n' "${TUNNELS[@]}" | grep -qxF -- "${1:-}" && exit 0

failed=()
for tun in "${TUNNELS[@]}"; do
    awg show "${tun}" &> /dev/null || continue
    log "NM event: ${1} ${2}, restarting ${tun}"
    if restart "${tun}"; then
        {
            printf 'Time: %s\n' "$(date -R)"
            printf 'Tunnel %s is back after %s of %s attempts.\n' "${tun}" "${ATTEMPTS}" "${MAX_ATTEMPTS}"
            printf 'Trigger: %s %s\n' "${1}" "${2}"
        } | send_mail "[watchdog] awg: ${tun} restored after ${ATTEMPTS} attempt(s)"
        notify normal "AmneziaWG: ${tun} restored" "${ATTEMPTS}/${MAX_ATTEMPTS} attempts"
    else
        failed+=("${tun}")
    fi
done

(( ${#failed[@]} )) || exit 0
rate_limited awg-restart 300 && exit 1

{
    printf 'Time: %s\n' "$(date -R)"
    printf 'No connectivity after %s attempts: %s\n\n' "${MAX_ATTEMPTS}" "${failed[*]}"
    tail -n 30 "${LOG}"
} | send_mail "[watchdog] awg: ${failed[*]} did not come up"
notify critical "AmneziaWG: ${failed[*]} down" "${MAX_ATTEMPTS} attempts failed"
exit 1
