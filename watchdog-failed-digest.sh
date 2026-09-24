#!/usr/bin/env bash
# Daily digest of failed systemd units (system + user scope).
set -euo pipefail

MAILBOX="/var/mail/silent"
# Runs from a system unit: point systemctl --user at the user manager.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"

notify() {
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}" \
        notify-send -u normal -a watchdog "${1}" "${2:-}" 2>/dev/null || true
}

sys_failed=$(systemctl list-units --state=failed --plain --no-legend --no-pager 2>/dev/null | awk '{print $1}' || true)
usr_failed=$(systemctl --user list-units --state=failed --plain --no-legend --no-pager 2>/dev/null | awk '{print $1}' || true)

[[ -z "${sys_failed}" && -z "${usr_failed}" ]] && exit 0

names=$(printf '%s\n%s\n' "${sys_failed}" "${usr_failed}" | grep '\S' | sed 's/\.service$//')
total=$(wc -l <<< "${names}")
name_list=$(paste -sd, <<< "${names}" | sed 's/,/, /g')

report() {
    local unit
    while IFS= read -r unit; do
        printf '\n=== %s ===\n' "${unit}"
        systemctl "$@" show "${unit}" --no-pager \
            -p Description,Result,ExecMainStatus,NRestarts,InactiveEnterTimestamp 2>/dev/null \
            | sed 's/^/  /' || true
        printf '\n'
        journalctl "$@" -u "${unit}" -n 10 --no-pager -o short-precise 2>/dev/null || true
    done
}

{
    printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
    printf 'From: watchdog@localhost\n'
    printf 'To: silent\n'
    printf 'Subject: [watchdog] %d failed unit(s): %s\n' "${total}" "${name_list}"
    printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
    printf '\n'
    printf 'Time: %s\n' "$(date -R)"
    printf 'After a fix: systemctl [--user] reset-failed <unit>\n'

    if [[ -n "${sys_failed}" ]]; then
        printf '\n%s\n' '--- System failed units ---'
        report <<< "${sys_failed}"
    fi

    if [[ -n "${usr_failed}" ]]; then
        printf '\n%s\n' '--- User failed units ---'
        report --user <<< "${usr_failed}"
    fi
    printf '\n'
} >> "${MAILBOX}"

notify "${total} failed unit(s)" "${name_list:0:80}"
