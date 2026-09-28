#!/usr/bin/env bash
# Watchdog for wl-paste clipboard daemons (not systemd services).
# Checks every 30s; on death attempts restart and mails only if that does not help.
set -euo pipefail
. /usr/local/lib/watchdog.sh

AUTO_RESTART=true  # set false to disable restart attempts

TEXT_ARGS=()
IMAGE_ARGS=()

learn_cmd() {
    local pat="$1" arr_var="$2"
    local pid
    pid=$(pgrep -f "${pat}" 2>/dev/null | head -1) || return 1
    readarray -d '' "${arr_var}" < "/proc/${pid}/cmdline"
}

mail_event() {
    local which="$1" status="$2"
    {
        printf 'Time: %s\n' "$(date -R)"
        printf 'Restart: %s\n' "${status:-disabled}"
        printf '\nRunning wl-paste processes:\n'
        pgrep -a wl-paste 2>/dev/null || printf '  (none)\n'
    } | send_mail "[watchdog] clipboard ${which} died${status:+ (${status})}"
    notify normal "Clipboard ${which} died" "${status}"
}

check_one() {
    local which="$1" pat="$2" args_name="$3"
    if pgrep -f "${pat}" > /dev/null 2>&1; then
        learn_cmd "${pat}" "${args_name}" 2>/dev/null || true
        return
    fi

    rate_limited "clipboard-${which}" 300 && return

    local status="not restarted"
    if [[ "${AUTO_RESTART}" == "true" ]]; then
        local -n args="${args_name}"
        if [[ ${#args[@]} -gt 0 ]]; then
            # A transient unit: outside this cgroup, with the manager's WAYLAND_DISPLAY.
            systemd-run --user --quiet --collect -- "${args[@]}" || true
            sleep 2
            pgrep -f "${pat}" > /dev/null 2>&1 && status="restarted" || status="restart failed"
            [[ "${status}" == "restarted" ]] && learn_cmd "${pat}" "${args_name}" 2>/dev/null || true
        else
            status="no saved command (started before watchdog?)"
        fi
    fi

    if [[ "${status}" == "restarted" ]]; then
        echo "clipboard ${which} died, restarted"
        return
    fi
    mail_event "${which}" "${status}"
}

learn_cmd 'wl-paste.*text'  TEXT_ARGS  2>/dev/null || true
learn_cmd 'wl-paste.*image' IMAGE_ARGS 2>/dev/null || true

while true; do
    # No compositor (logged out) or it is still starting wl-paste: nothing to check.
    hypr=$(pgrep -xo Hyprland || true)
    if [[ -z "${hypr}" ]] || (( $(ps -o etimes= -p "${hypr}" || echo 0) < 60 )); then
        sleep 30
        continue
    fi
    check_one "text"  'wl-paste.*text'  TEXT_ARGS
    check_one "image" 'wl-paste.*image' IMAGE_ARGS
    sleep 30
done
