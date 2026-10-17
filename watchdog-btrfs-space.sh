#!/usr/bin/env bash
# Keep unallocated space on btrfs above max(MIN_PCT% of device, MIN_GIB) with a stepwise data balance.
# Never deletes anything: when balance cannot help, it mails what fills the disk.
set -euo pipefail
. /usr/local/lib/watchdog.sh

MOUNTS=("/")
MIN_PCT=5
MIN_GIB=10
STEPS=(0 5 10 20 30 40 50)
REMAIL_GIB=5
load_config btrfs-space
STATE_DIR="${STATE_DIRECTORY:-/var/lib/watchdog-btrfs-space}"

GIB=$((1024 ** 3))

unallocated() {
    btrfs filesystem usage -b "${1}" 2>/dev/null | awk -F: '/Device unallocated/ {print $2 + 0}'
}

gib() {
    echo $(( ${1} / GIB ))
}

snapshot_hint() {
    local cfg
    cfg=$(grep -lx "SUBVOLUME=\"${1}\"" /etc/snapper/configs/* 2>/dev/null | head -n1 || true)
    [[ -z "${cfg}" ]] && return 0
    printf 'snapper config %s: %s snapshot(s)\n' "$(basename "${cfg}")" \
        "$(snapper -c "$(basename "${cfg}")" list --disable-used-space 2>/dev/null | tail -n +3 | wc -l)"
}

for mnt in "${MOUNTS[@]}"; do
    [[ "$(findmnt -n -o FSTYPE "${mnt}" 2>/dev/null)" == btrfs ]] || continue

    size=$(btrfs filesystem usage -b "${mnt}" | awk -F: '/Device size/ {print $2 + 0}')
    limit=$(( size * MIN_PCT / 100 ))
    (( limit < MIN_GIB * GIB )) && limit=$(( MIN_GIB * GIB ))
    state="${STATE_DIR}/${mnt//\//_}"

    before=$(unallocated "${mnt}")
    if (( before >= limit )); then
        rm -f "${state}"
        continue
    fi

    read -r data_total data_used < <(btrfs filesystem df -b "${mnt}" \
        | awk -F'[=,]' '/^Data/ {print $3 + 0, $5 + 0}')

    steps_done=()
    if (( data_total - data_used >= GIB )); then
        for step in "${STEPS[@]}"; do
            echo "${mnt}: balance -dusage=${step}"
            if btrfs balance start -dusage="${step}" "${mnt}"; then
                steps_done+=("${step}")
            else
                steps_done+=("${step}(failed)")
            fi
            (( $(unallocated "${mnt}") >= limit )) && break
        done
    fi

    after=$(unallocated "${mnt}")
    freed=$(( after - before ))

    if (( after >= limit )); then
        rm -f "${state}"
        subject="btrfs ${mnt}: balance freed $(gib "${freed}") GiB, unallocated $(gib "${after}") GiB"
        urgency=normal
    else
        last=$(cat "${state}" 2>/dev/null || echo -1)
        if (( freed < GIB && last >= 0 && $(gib "${after}") > last - REMAIL_GIB )); then
            continue
        fi
        gib "${after}" > "${state}"
        subject="btrfs ${mnt}: unallocated $(gib "${after}") GiB below $(gib "${limit}") GiB, free space by hand"
        urgency=critical
    fi

    {
        printf 'Time: %s\n\n' "$(date -R)"
        printf 'Unallocated: %s GiB -> %s GiB (limit %s GiB)\n' \
            "$(gib "${before}")" "$(gib "${after}")" "$(gib "${limit}")"
        printf 'Data chunks: %s GiB allocated, %s GiB used\n' "$(gib "${data_total}")" "$(gib "${data_used}")"
        if (( ${#steps_done[@]} )); then
            printf 'Balance steps (-dusage): %s\n' "${steps_done[*]}"
        else
            printf 'Balance skipped: data chunks are full, only deleting data frees space.\n'
        fi
        snapshot_hint "${mnt}"
        if [[ "${urgency}" == critical ]]; then
            printf '\nNothing was deleted. Find what fills %s: btdu %s, ncdu -x %s\n' "${mnt}" "${mnt}" "${mnt}"
        fi
        printf '\n'
        btrfs filesystem usage "${mnt}" 2>/dev/null | sed -n '1,/^$/p'
        df -h "${mnt}"
    } | send_mail "[watchdog] ${subject}"

    notify "${urgency}" "${subject}" ""
done
