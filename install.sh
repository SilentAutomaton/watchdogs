#!/usr/bin/env bash
# Install the watchdogs for one user: sudo ./install.sh <user>
# Copies scripts and units, fills @USER@, keeps existing /etc/watchdogs/*.conf. Enables nothing.
set -euo pipefail

USER_NAME="${1:?usage: install.sh <user>}"
[[ "${USER_NAME}" =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo "install.sh: bad user name" >&2; exit 1; }
id -u "${USER_NAME}" > /dev/null
(( EUID == 0 )) || { echo "install.sh: run as root" >&2; exit 1; }
cd "$(dirname "$0")"

USER_HOME=$(getent passwd "${USER_NAME}" | cut -d: -f6)
USER_UNITS="${USER_HOME}/.config/systemd/user"
USER_SERVICES=(watchdog-clipboard.service watchdog-hyprland.service watchdog-mic-volume.service)

fill() { sed "s/@USER@/${USER_NAME}/g" "$1"; }

install -Dm644 watchdog-lib.sh /usr/local/lib/watchdog.sh
for f in notify-failure.sh watchdog-*.sh; do
    [[ "${f}" == watchdog-lib.sh ]] && continue
    install -Dm755 "${f}" "/usr/local/bin/${f%.sh}"
done
install -Dm755 clamav-pacman-scan.sh /usr/local/bin/clamav-pacman-scan.sh
install -Dm755 awg-restart.sh /etc/NetworkManager/dispatcher.d/99-awg-restart

for f in *.service *.timer; do
    [[ "${f}" == notify-failure-user@.service || " ${USER_SERVICES[*]} " == *" ${f} "* ]] && continue
    fill "${f}" | install -Dm644 /dev/stdin "/etc/systemd/system/${f}"
done

install -d -o "${USER_NAME}" -g "${USER_NAME}" "${USER_HOME}/.config" "${USER_HOME}/.config/systemd" "${USER_UNITS}"
install -m644 -o "${USER_NAME}" -g "${USER_NAME}" notify-failure-user@.service "${USER_UNITS}/notify-failure@.service"
for f in "${USER_SERVICES[@]}"; do
    install -m644 -o "${USER_NAME}" -g "${USER_NAME}" "${f}" "${USER_UNITS}/${f}"
done

sudoers=$(mktemp)
trap 'rm -f "${sudoers}"' EXIT
fill watchdog-btrfs-sudoers > "${sudoers}"
visudo -cqf "${sudoers}"
install -m440 "${sudoers}" /etc/sudoers.d/watchdog-btrfs

fill watchdog-rate.conf | install -Dm644 /dev/stdin /etc/tmpfiles.d/watchdog-rate.conf
systemd-tmpfiles --create /etc/tmpfiles.d/watchdog-rate.conf

install -d -m755 /etc/watchdogs
[[ -e /etc/watchdogs/common.conf ]] \
    || printf 'WATCHDOG_USER="%s"\n' "${USER_NAME}" | install -m644 /dev/stdin /etc/watchdogs/common.conf

systemctl daemon-reload
echo "Done. As ${USER_NAME}, run: systemctl --user daemon-reload"
echo "Settings: examples/*.conf.example -> /etc/watchdogs/<name>.conf"
