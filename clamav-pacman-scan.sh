#!/bin/bash
. /usr/local/lib/watchdog.sh

mail_threat() {
    local pkg="$1" findings="$2"
    {
        printf 'Package: %s\n' "${pkg}"
        printf 'Time:    %s\n' "$(date -R)"
        printf '\n--- ClamAV findings ---\n\n'
        printf '%s\n' "${findings}"
    } | send_mail "[clamav] threat found in package: ${pkg}"
}

while read -r pkg; do
    pacman -Qqm "$pkg" >/dev/null 2>&1 || continue
    files=$(pacman -Qlq "$pkg" 2>/dev/null | grep -v '/$')
    [ -z "$files" ] && continue

    output=$(ionice -c3 nice -n19 clamscan --infected --no-summary --file-list=<(printf '%s\n' "${files}") 2>/dev/null || true)
    findings=$(printf '%s' "${output}" | grep -v '^$' || true)

    if [ -n "${findings}" ]; then
        printf '%s\n' "${findings}" | systemd-cat -t clamav-pacman -p warning
        mail_threat "${pkg}" "${findings}"
    fi
done
