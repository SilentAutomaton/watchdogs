# Sourced by every watchdog: . /usr/local/lib/watchdog.sh

CONF_DIR="/etc/watchdogs"
WATCHDOG_USER=""
[[ -r "${CONF_DIR}/common.conf" ]] && . "${CONF_DIR}/common.conf"
if [[ -z "${WATCHDOG_USER}" ]]; then
    echo "watchdog: set WATCHDOG_USER in ${CONF_DIR}/common.conf" >&2
    exit 1
fi

MAILBOX="/var/mail/${WATCHDOG_USER}"
USER_RUNTIME_DIR="/run/user/$(id -u "${WATCHDOG_USER}")"
RATE_DIR="/run/watchdog-rate"

# Sourced after a script sets its defaults: /etc/watchdogs/<name>.conf overrides them.
load_config() {
    local f="${CONF_DIR}/${1}.conf"
    [[ -r "${f}" ]] && . "${f}"
    return 0
}

# Root cannot append to another user's file in sticky /var/mail (fs.protected_regular).
as_user() {
    if (( EUID == 0 )); then
        runuser -u "${WATCHDOG_USER}" -- "$@"
    else
        "$@"
    fi
}

notify() {
    as_user env DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${USER_RUNTIME_DIR}/bus}" \
        notify-send -u "${1}" -a watchdog "${2}" "${3:-}" 2>/dev/null || true
}

send_mail() {
    {
        printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
        printf 'From: watchdog@localhost\n'
        printf 'To: %s\n' "${WATCHDOG_USER}"
        printf 'Subject: %s\n' "${1}"
        printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
        printf '\n'
        cat
        printf '\n'
    } | as_user tee -a "${MAILBOX}" >/dev/null
}

# Succeeds while KEY fired less than TTL seconds ago; otherwise stamps KEY and fails.
rate_limited() {
    local stamp="${RATE_DIR}/${1}" now last
    now=$(date +%s)
    last=$(cat "${stamp}" 2>/dev/null || echo 0)
    (( now - last < ${2} )) && return 0
    echo "${now}" > "${stamp}"
    return 1
}
