#!/usr/bin/env bash
# Watchdog for Hyprland compositor process (not a systemd unit).
# A normal logout also ends Hyprland; only a crash report or a coredump means a crash.
set -euo pipefail
. /usr/local/lib/watchdog.sh

AUTO_RESTART=false  # set true to relaunch Hyprland after crash (kills all child apps)
CRASH_DIR="${HOME}/.cache/hyprland"

mail_crash() {
    local report="$1" coredump="$2" last_seen="$3"
    {
        printf 'Time:         %s\n' "$(date -R)"
        printf 'Crash report: %s\n' "${report:-none}"
        printf 'Coredump:     %s\n' "${coredump:+yes, see coredumpctl info Hyprland}"
        if [[ -n "${report}" ]]; then
            printf '\n%s\n\n' '--- Crash report (first 60 lines) ---'
            head -n 60 "${report}"
        fi
        if [[ -n "${coredump}" ]]; then
            printf '\n%s\n\n' '--- coredumpctl ---'
            printf '%s\n' "${coredump}"
        fi
        printf '\n%s\n\n' '--- Journal context (60s before crash) ---'
        journalctl --user --no-pager -o short-precise \
            --since "@$(( last_seen - 60 ))" --until "@$(( last_seen + 10 ))" 2>/dev/null \
            | grep -v '^-- ' || true
    } | send_mail "[watchdog] Hyprland crashed"
}

check_crash() {
    local report coredump
    report=$(find "${CRASH_DIR}" -maxdepth 1 -name 'hyprlandCrashReport*.txt' \
        -newermt "@${started}" 2>/dev/null | head -1 || true)
    coredump=$(coredumpctl -q --no-pager list Hyprland --since "@${started}" 2>/dev/null || true)
    [[ -z "${report}${coredump}" ]] && return 0

    rate_limited hyprland 120 && return 0

    mail_crash "${report}" "${coredump}" "${last_seen}"
    notify critical "Hyprland crashed" "${report:-coredump}"
    if [[ "${AUTO_RESTART}" == "true" ]]; then
        Hyprland &
    fi
}

pid=""
started=0
last_seen=0

while true; do
    current=$(pgrep -xo Hyprland || true)
    # Gone, or replaced by a new instance (quick relogin): check the old one.
    if [[ -n "${pid}" && "${current}" != "${pid}" ]]; then
        check_crash
        pid=""
    fi
    if [[ -n "${current}" ]]; then
        [[ -z "${pid}" ]] && pid="${current}" started=$(date +%s)
        last_seen=$(date +%s)
    fi
    sleep 10
done
