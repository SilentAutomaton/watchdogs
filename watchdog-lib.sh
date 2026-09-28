# Sourced by every watchdog: . /usr/local/lib/watchdog.sh

MAILBOX="/var/mail/silent"
RATE_DIR="/run/watchdog-rate"

# Root cannot append to another user's file in sticky /var/mail (fs.protected_regular).
as_silent() {
    if (( EUID == 0 )); then
        runuser -u silent -- "$@"
    else
        "$@"
    fi
}

notify() {
    as_silent env DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}" \
        notify-send -u "${1}" -a watchdog "${2}" "${3:-}" 2>/dev/null || true
}

send_mail() {
    {
        printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
        printf 'From: watchdog@localhost\n'
        printf 'To: silent\n'
        printf 'Subject: %s\n' "${1}"
        printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
        printf '\n'
        cat
        printf '\n'
    } | as_silent tee -a "${MAILBOX}" >/dev/null
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
