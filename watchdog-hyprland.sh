#!/usr/bin/env bash
# Watchdog for Hyprland compositor process (not a systemd unit).
# A normal logout also ends Hyprland; only a crash report or a coredump means a crash.
set -euo pipefail

AUTO_RESTART=false  # set true to relaunch Hyprland after crash (kills all child apps)
MAILBOX="/var/mail/silent"
RATE_FILE="/run/watchdog-rate/hyprland"
RATE_TTL=120
CRASH_DIR="${HOME}/.cache/hyprland"

notify() {
    notify-send -u critical -a watchdog "${1}" "${2:-}" 2>/dev/null || true
}

mail_crash() {
    local report="$1" coredump="$2" last_seen="$3"
    {
        printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
        printf 'From: watchdog@localhost\n'
        printf 'To: silent\n'
        printf 'Subject: [watchdog] Hyprland crashed\n'
        printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
        printf '\n'
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
        printf '\n'
    } >> "${MAILBOX}"
}

check_crash() {
    local report coredump now last
    report=$(find "${CRASH_DIR}" -maxdepth 1 -name 'hyprlandCrashReport*.txt' \
        -newermt "@${started}" 2>/dev/null | head -1 || true)
    coredump=$(coredumpctl -q --no-pager list Hyprland --since "@${started}" 2>/dev/null || true)
    [[ -z "${report}${coredump}" ]] && return 0

    now=$(date +%s)
    last=$(cat "${RATE_FILE}" 2>/dev/null || echo 0)
    (( now - last < RATE_TTL )) && return 0
    echo "${now}" > "${RATE_FILE}"

    mail_crash "${report}" "${coredump}" "${last_seen}"
    notify "Hyprland crashed" "${report:-coredump}"
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
