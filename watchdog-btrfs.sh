#!/usr/bin/env bash
# Filesystem health watchdog: BTRFS (device stats + scrub) and ext4 (state + journal errors).
set -euo pipefail

MAILBOX="/var/mail/silent"
MOUNTS=("/" "/home" "/mnt")

errors=""
scrub_issues=""
summary=()

notify() {
    DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}" \
        notify-send -u critical -a watchdog "${1}" "${2:-}" 2>/dev/null || true
}

check_btrfs() {
    local mnt="$1"
    local dev_err scrub
    dev_err=$(sudo btrfs device stats "${mnt}" 2>/dev/null \
        | awk '$NF+0 != 0 {print}' || true)
    if [[ -n "${dev_err}" ]]; then
        errors+=$'\n'"${mnt} device errors:"$'\n'"${dev_err}"
        summary+=("${mnt}: $(wc -l <<< "${dev_err}") device error counter(s)")
    fi

    # "no stats available" only means scrub has not run yet: not a problem.
    scrub=$(sudo btrfs scrub status "${mnt}" 2>/dev/null || true)
    local state=""
    if [[ "${scrub,,}" =~ aborted|interrupted ]]; then
        state="scrub aborted"
    elif [[ "${scrub}" == *"Error summary:"* && "${scrub}" != *"no errors found"* ]]; then
        state="scrub found errors"
    fi
    if [[ -n "${state}" ]]; then
        scrub_issues+=$'\n'"${mnt} scrub:"$'\n'"${scrub}"
        summary+=("${mnt}: ${state}")
    fi
    return 0
}

check_ext4() {
    local mnt="$1"
    local dev state journal_errs dev_base
    dev=$(findmnt -n -o SOURCE "${mnt}" 2>/dev/null || true)
    [[ -z "${dev}" ]] && return 0

    state=$(sudo tune2fs -l "${dev}" 2>/dev/null \
        | awk -F': +' '/Filesystem state/{print $2}' || true)
    if [[ -n "${state}" && "${state}" != "clean" ]]; then
        errors+=$'\n'"${mnt} (${dev}) state: ${state}"
        summary+=("${mnt}: state ${state}")
    fi

    dev_base=$(basename "${dev}")
    journal_errs=$(journalctl -k --since "7 days ago" --no-pager -o short-precise 2>/dev/null \
        | grep -E "EXT4-fs error|I/O error.*${dev_base}" || true)
    if [[ -n "${journal_errs}" ]]; then
        errors+=$'\n'"${mnt} (${dev}) kernel errors:"$'\n'"${journal_errs}"
        summary+=("${mnt}: $(wc -l <<< "${journal_errs}") kernel error(s) in 7 days")
    fi
    return 0
}

for mnt in "${MOUNTS[@]}"; do
    [[ -d "${mnt}" ]] || continue
    mountpoint -q "${mnt}" 2>/dev/null || continue

    fstype=$(findmnt -n -o FSTYPE "${mnt}" 2>/dev/null || true)
    case "${fstype}" in
        btrfs) check_btrfs "${mnt}" ;;
        ext4)  check_ext4  "${mnt}" ;;
    esac
done

(( ${#summary[@]} )) || exit 0

subject="filesystem: $(printf '%s; ' "${summary[@]}")"
subject="${subject%; }"

{
    printf 'From MAILER-DAEMON %s\n' "$(date '+%a %b %e %H:%M:%S %Y')"
    printf 'From: watchdog@localhost\n'
    printf 'To: silent\n'
    printf 'Subject: [watchdog] %s\n' "${subject}"
    printf 'Date: %s\n' "$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
    printf '\n'
    printf 'Time: %s\n\n' "$(date -R)"
    printf '%s\n' "${summary[@]}"
    [[ -n "${errors}" ]]       && printf '\n--- Errors ---\n%s\n' "${errors}"
    [[ -n "${scrub_issues}" ]] && printf '\n--- Scrub status ---\n%s\n' "${scrub_issues}"
    printf '\n'
} >> "${MAILBOX}"

notify "${subject}" ""
