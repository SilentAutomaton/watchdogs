#!/usr/bin/env bash
# Called by systemd OnFailure=: notify-failure [--user] %i.
# systemd passes the failed unit and its result in MONITOR_* variables.
set -euo pipefail

SYSTEM_STATE=$(systemctl is-system-running 2>/dev/null || true)
if [[ "${SYSTEM_STATE}" == "stopping" || "${SYSTEM_STATE}" == "maintenance" ]]; then
    exit 0
fi

AUTO_RESTART=false  # set true to attempt systemctl restart on failure

scope=()
if [[ "${1:-}" == "--user" ]]; then
    scope=(--user)
    shift
fi

UNIT="${MONITOR_UNIT:-${1:-unknown}.service}"
MAILBOX="/var/mail/silent"
RATE_FILE="/run/watchdog-rate/${UNIT}"
RATE_TTL=300

notify() {
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}" \
        notify-send -u critical -a watchdog "${1}" "${2:-}" 2>/dev/null || true
}

now=$(date +%s)
if [[ -f "${RATE_FILE}" ]]; then
    last=$(< "${RATE_FILE}")
    (( now - last < RATE_TTL )) && exit 0
fi
echo "${now}" > "${RATE_FILE}"

RESULT="${MONITOR_SERVICE_RESULT:-$(systemctl "${scope[@]}" show -p Result --value "${UNIT}" 2>/dev/null || true)}"
EXIT="${MONITOR_EXIT_CODE:-?} ${MONITOR_EXIT_STATUS:-}"
RESTARTS=$(systemctl "${scope[@]}" show -p NRestarts --value "${UNIT}" 2>/dev/null || true)
DESCRIPTION=$(systemctl "${scope[@]}" show -p Description --value "${UNIT}" 2>/dev/null || true)
STATUS=$(systemctl "${scope[@]}" status "${UNIT}" --no-pager -l -n 0 2>/dev/null || true)
LOGS=$(journalctl "${scope[@]}" -u "${UNIT}" -n 30 --no-pager -o short-precise 2>/dev/null || true)

{
    printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
    printf 'From: watchdog@localhost\n'
    printf 'To: silent\n'
    printf 'Subject: [watchdog] %s failed: %s\n' "${UNIT}" "${RESULT:-unknown}"
    printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
    printf '\n'
    printf 'Unit:     %s%s\n' "${UNIT}" "${scope:+ (user)}"
    printf 'What:     %s\n' "${DESCRIPTION:-?}"
    printf 'Result:   %s\n' "${RESULT:-?}"
    printf 'Exit:     %s\n' "${EXIT}"
    printf 'Restarts: %s\n' "${RESTARTS:-?}"
    printf 'Time:     %s\n' "$(date -R)"
    printf '\n%s\n\n' '--- systemctl status ---'
    printf '%s\n' "${STATUS:-(status unavailable)}"
    printf '\n%s\n\n' '--- Last 30 journal lines ---'
    printf '%s\n' "${LOGS:-(no journal entries found)}"
    printf '\n'
} >> "${MAILBOX}"

notify "${UNIT} failed" "${RESULT:-unknown}, exit ${EXIT}"

if [[ "${AUTO_RESTART}" == "true" ]]; then
    systemctl "${scope[@]}" restart "${UNIT}" 2>/dev/null || true
fi
