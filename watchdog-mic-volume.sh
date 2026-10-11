#!/usr/bin/env bash
# Holds the built-in webcam mic volume at one level. WirePlumber resets it to 100%
# when Bluetooth headphones connect or disconnect.
# A mic in the jack uses the same source on another port and is left alone.
set -euo pipefail
. /usr/local/lib/watchdog.sh

SOURCE="alsa_input.pci-0000_00_1f.3.analog-stereo"
PORT="analog-input-internal-mic"
VOLUME="50%"

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
