#!/usr/bin/env bash
# Polls sshd journal for logins and brute-force attempts every 60s.
# Works even when sshd is stopped — journal just returns nothing.
set -euo pipefail
. /usr/local/lib/watchdog.sh

CURSOR_FILE="${STATE_DIRECTORY:-/var/lib/watchdog-ssh}/cursor"
FAILED_THRESHOLD=10

parse_entries() {
    python3 -c "
import sys, json, re

logins = []
failed = 0

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
        msg = d.get('MESSAGE', '')
        ts  = int(d.get('_SOURCE_REALTIME_TIMESTAMP') or d.get('__REALTIME_TIMESTAMP', 0)) // 1000000
        m = re.search(r'Accepted (\S+) for (\S+) from ([\d.a-f:]+)', msg)
        if m:
            logins.append((ts, m.group(1), m.group(2), m.group(3)))
        elif re.search(r'Failed (password|publickey)|Invalid user', msg):
            failed += 1
    except Exception:
        pass

for ts, method, user, ip in logins:
    print(f'LOGIN\t{ts}\t{method}\t{user}\t{ip}')
if failed >= int(sys.argv[1]):
    print(f'FAILED\t{failed}')
" "${FAILED_THRESHOLD}" 2>/dev/null
}

mail_login() {
    local ts="$1" method="$2" user="$3" ip="$4"
    local when
    when=$(date -d "@${ts}" -R 2>/dev/null || date -R)
    {
        printf 'User:   %s\n' "${user}"
        printf 'From:   %s\n' "${ip}"
        printf 'Method: %s\n' "${method}"
        printf 'When:   %s\n' "${when}"
    } | send_mail "[ssh] login: ${user} from ${ip} (${method})"
    notify normal "SSH login: ${user}@${ip}" "${method}"
}

mail_bruteforce() {
    local count="$1"
    {
        printf 'Time: %s\n\n' "$(date -R)"
        journalctl -u sshd.service -n 30 --no-pager -o short-precise \
            | grep -E 'Failed|Invalid|error' || true
    } | send_mail "[ssh] ${count} failed attempts in 60s"
    notify critical "SSH: ${count} failed attempts" ""
}

# First start: skip old logins, watch only new ones.
[[ -f "${CURSOR_FILE}" ]] || journalctl -u sshd.service -n 0 --cursor-file="${CURSOR_FILE}" --no-pager >/dev/null

while true; do
    entries=$(journalctl -u sshd.service --cursor-file="${CURSOR_FILE}" --no-pager -o json 2>/dev/null || true)

    if [[ -n "${entries}" ]]; then
        while IFS=$'\t' read -r type rest; do
            case "${type}" in
                LOGIN)
                    IFS=$'\t' read -r ts method user ip <<< "${rest}"
                    mail_login "${ts}" "${method}" "${user}" "${ip}"
                    ;;
                FAILED)
                    mail_bruteforce "${rest}"
                    ;;
            esac
        done < <(echo "${entries}" | parse_entries)
    fi

    sleep 60
done
