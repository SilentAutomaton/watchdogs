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

# Usage: awg_tunnels RULE [TUNNEL...]. With RULE set, the interfaces come from the iface.out
# regex ^(lo|wg0|wg1)$ of that opensnitch rule; otherwise they are the arguments.
awg_tunnels() {
    local rule="$1"
    shift
    if [[ -n "${rule}" ]]; then
        jq -r '.operator.list[] | select(.operand == "iface.out") | .data' "${rule}" \
            | sed -E 's/^\^\(//; s/\)\$$//' | tr '|' '\n' | sed '/^lo$/d'
    elif (( $# )); then
        printf '%s\n' "$@"
    fi
}

# A new interface gets a new random source port: the only heal for a UDP flow frozen by TSPU.
# "awg set listen-port" on a live amneziawg-go 3.1 interface stops all data instead.
# Usage: awg_restart_tunnel TUN [UNIT]. UNIT defaults to awg-quick@TUN.service when that is active.
# Children get fd 9 closed: amneziawg-go would otherwise hold the lock for its whole life.
awg_restart_tunnel() {
    local tun="$1" unit="${2:-awg-quick@${1}.service}"
    (
        flock 9
        if systemctl -q is-active "${unit}"; then
            systemctl restart "${unit}" 9>&-
        else
            awg-quick down "${tun}" 9>&- || true
            # A scope of its own keeps amneziawg-go out of the caller's cgroup,
            # which systemd cleans up when the caller's unit stops.
            systemd-run --scope --quiet --collect awg-quick up "${tun}" 9>&-
        fi
    ) 9> "/run/awg-restart.${tun}.lock"
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
