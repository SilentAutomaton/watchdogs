#!/usr/bin/env bash
# Remind to sync the clock when the last NTP sync is older than MAX_DAYS.
# timesyncd runs only on demand (sync-time), so this watchdog reads the journal
# and never sends a packet itself.
set -euo pipefail
. /usr/local/lib/watchdog.sh

MAX_DAYS=7
load_config clock

last=$(journalctl -u systemd-timesyncd -g 'Initial clock synchronization' -n 1 -q -o short-unix | cut -d. -f1)
if [[ -z "${last}" ]]; then
    notify normal "Clock never synced" "The journal has no NTP sync. Run sync-time to sync it once."
    exit 0
fi

days=$(( ($(date +%s) - last) / 86400 ))
(( days >= MAX_DAYS )) || exit 0
notify normal "Clock not synced for ${days} days" "Run sync-time to sync it once."
