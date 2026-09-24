#!/bin/bash
MAILBOX=/var/mail/silent

mail_threat() {
    local pkg="$1" findings="$2"
    {
        printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
        printf 'From: watchdog@localhost\n'
        printf 'To: silent\n'
        printf 'Subject: [clamav] threat found in package: %s\n' "${pkg}"
        printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
        printf '\n'
        printf 'Package: %s\n' "${pkg}"
        printf 'Time:    %s\n' "$(date -R)"
        printf '\n--- ClamAV findings ---\n\n'
        printf '%s\n' "${findings}"
        printf '\n'
    } >> "${MAILBOX}"
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
