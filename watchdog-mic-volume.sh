#!/usr/bin/env bash
# Holds the built-in webcam mic volume at one level. WirePlumber resets it to 100%
# when Bluetooth headphones connect or disconnect.
# A mic in the jack uses the same source on another port and is left alone.
set -euo pipefail
. /usr/local/lib/watchdog.sh

SOURCE=""
PORT=""
VOLUME="50%"
load_config mic-volume
if [[ -z "${SOURCE}" || -z "${PORT}" ]]; then
    echo "watchdog-mic-volume: set SOURCE and PORT in ${CONF_DIR}/mic-volume.conf" >&2
    exit 1
fi

hold() {
    local state port current
    state=$(pactl -f json list sources 2>/dev/null \
        | jq -r --arg s "${SOURCE}" '.[] | select(.name == $s) | .active_port, ([.volume[].value_percent] | unique | join(","))' || true)
    { read -r port; read -r current; } <<< "${state}" || return 0
    [[ "${port}" != "${PORT}" || -z "${current}" || "${current}" == "${VOLUME}" ]] && return
    pactl set-source-volume "${SOURCE}" "${VOLUME}" || return 0
    notify low "Mic volume reset" "${current} → ${VOLUME}"
}

hold
pactl subscribe | while read -r line; do
    [[ "${line}" == *" on source "* || "${line}" == *" on server"* || "${line}" == *" on card "* ]] && hold
done
