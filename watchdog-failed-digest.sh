#!/usr/bin/env bash
# Daily digest of failed systemd units (system + user scope).
set -euo pipefail
. /usr/local/lib/watchdog.sh

# Runs from a system unit: point systemctl --user at the user manager.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"

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
} | send_mail "[watchdog] ${total} failed unit(s): ${name_list}"

notify normal "${total} failed unit(s)" "${name_list:0:80}"
