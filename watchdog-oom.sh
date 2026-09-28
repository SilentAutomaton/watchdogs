#!/usr/bin/env bash
# Polls journal for OOM events every 60s instead of streaming (saves ~50MB RAM).
set -euo pipefail
. /usr/local/lib/watchdog.sh

CURSOR_FILE="${STATE_DIRECTORY:-/var/lib/watchdog-oom}/cursor"

human() {
    numfmt --from-unit=1024 --to=iec-i --suffix=B --format='%.1f' "$1" 2>/dev/null || echo "$1 kB"
}

parse_oom_events() {
    local killed_lines
    killed_lines=$(journalctl -k --cursor-file="${CURSOR_FILE}" --no-pager -o json 2>/dev/null \
        | python3 -c "
import sys, json, re
for line in sys.stdin:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    msg = d.get('MESSAGE', '')
    m = re.search(r'Killed process (\d+) \((.+?)\) total-vm:(\d+)kB, anon-rss:(\d+)kB, '
                  r'file-rss:(\d+)kB, shmem-rss:(\d+)kB, UID:(\d+)', msg)
    if m:
        print(d.get('__REALTIME_TIMESTAMP', '0'), *m.groups(), sep='\t')
") || return 0

    [[ -z "${killed_lines}" ]] && return 0

    local ts pid proc vm anon file shmem uid
    while IFS=$'\t' read -r ts pid proc vm anon file shmem uid; do
        local secs=$(( ts / 1000000 ))
        local when rss context memcg invoker dump
        when=$(date -d "@${secs}" -R)
        rss=$(human $(( anon + file + shmem )))
        context=$(journalctl -k --no-pager -o short-precise \
            --since "@$(( secs - 5 ))" --until "@$(( secs + 2 ))" 2>/dev/null || true)
        memcg=$(grep -oP 'task_memcg=\K[^,]+' <<< "${context}" | tail -1 || true)
        invoker=$(grep -oP 'kernel: \K\S+(?= invoked oom-killer)' <<< "${context}" | tail -1 || true)
        dump=$(grep -E 'invoked oom-killer|oom-kill:|Out of memory|oom_reaper' <<< "${context}" \
            || echo "(no dump available)")

        {
            printf 'Killed:    %s (PID %s, UID %s)\n' "${proc}" "${pid}" "${uid}"
            printf 'When:      %s\n' "${when}"
            printf 'RSS:       %s = anon %s + file %s + shmem %s\n' \
                "${rss}" "$(human "${anon}")" "$(human "${file}")" "$(human "${shmem}")"
            printf 'Virtual:   %s\n' "$(human "${vm}")"
            printf 'Cgroup:    %s\n' "${memcg:-?}"
            printf 'Triggered: %s (process that asked for memory)\n' "${invoker:-?}"
            printf '\n%s\n\n' '--- Kernel log ---'
            printf '%s\n' "${dump}"
        } | send_mail "[watchdog] OOM: ${proc} (PID ${pid}) killed, ${rss} RSS"

        notify critical "OOM: ${proc} killed" "${rss} RSS, cgroup ${memcg:-?}"
    done <<< "${killed_lines}"
}

# First start: skip old events, watch only new ones.
[[ -f "${CURSOR_FILE}" ]] || journalctl -k -n 0 --cursor-file="${CURSOR_FILE}" --no-pager >/dev/null

while true; do
    parse_oom_events
    sleep 60
done
