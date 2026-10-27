[Русская версия](README.ru.md)

# watchdogs

Small systemd watchdogs for an Arch Linux desktop. When something breaks, they
put a letter in the local mailbox (`/var/mail/<user>`, read with `mail`) and show
a desktop notification. There is no mail server and nothing leaves the machine.

These are my personal tools. You are free to use them and change them however
you like, but they are not meant to be universal: the list of watched services
and some checks fit my machine only. Read a script before you copy it.

They are now a little easier to reuse. The user name, mount points and other
settings live in `/etc/watchdogs/*.conf` instead of the scripts, and
`install.sh` puts the files in place.

## What is watched

| Piece | How it runs | What it does |
|---|---|---|
| `notify-failure` | `OnFailure=` drop-ins in `drop-ins/` | A unit failed: mails `systemctl status` and the last 30 journal lines |
| `watchdog-failed-digest` | daily timer | Mails the list of failed system and user units, only when the list changed |
| `watchdog-oom` | service, polls every 60 s | One letter per OOM kill: process, PID, memory, cgroup, who triggered it |
| `watchdog-disk` | timer, 08:00, 14:00, 20:00 | A filesystem crossed 90%, then again for every 2 more points |
| `watchdog-btrfs` | weekly timer | BTRFS device error counters and scrub results, ext4 state; mails only on a problem |
| `watchdog-btrfs-space` | daily timer, root | Unallocated BTRFS space fell below max(5%, 10 GiB): runs a stepwise data balance. Never deletes anything; if balance does not help, mails what fills the disk |
| `watchdog-clock` | daily timer | The last NTP sync is older than 7 days: a notification to run `sync-time`. Reads only the journal, sends nothing |
| `watchdog-ssh` | service, runs while sshd runs, polls every 60 s | A letter for every successful SSH login, an alert at 10 failed attempts in a minute |
| `watchdog-clipboard` | user service | Restarts dead `wl-paste` clipboard daemons; mails only if the restart fails |
| `watchdog-hyprland` | user service | A Hyprland crash report or coredump appeared. A normal logout is not a crash |
| `watchdog-mic-volume` | user service | Holds the built-in webcam mic volume at 50% and shows a notification on each reset. WirePlumber resets it to 100% when Bluetooth headphones connect or disconnect. A mic in the jack is left alone |
| `clamav-pacman-scan.sh` | pacman hook | Scans foreign (AUR) packages after install with ClamAV |
| `watchdog-awg` | timer every 10 s, root | Pings through each AmneziaWG tunnel that is up. A tunnel that passes no data (a UDP flow frozen by TSPU) is restarted for a new source port; while it stays down, the next restart waits 30 s, doubling up to 5 min. Notifies on every heal; also mails after 3 failed restarts |
| `awg-restart.sh` | NetworkManager dispatcher | When an uplink comes up, restarts the AmneziaWG tunnels that stopped passing traffic, up to 5 tries |

Shared code lives in `watchdog-lib.sh`: the mail writer, the desktop
notification and a rate limit. `notify-failure` and `watchdog-clipboard` send
the same event at most once in 5 minutes. The stamps live in `/run/watchdog-rate`,
which `watchdog-rate.conf` creates through tmpfiles.d.

`notify-failure` stays silent while the system is stopping or in maintenance
mode, so a shutdown does not flood the mailbox.

`AUTO_RESTART` in `/etc/watchdogs/notify-failure.conf`, `clipboard.conf` and
`hyprland.conf` turns automatic restarts on or off.

## Settings

Each script keeps its defaults at the top. A file `/etc/watchdogs/<name>.conf`
overrides them; `examples/<name>.conf.example` lists the settings of each
watchdog. `common.conf` with `WATCHDOG_USER` is required by all of them.
`mic-volume.conf` (`SOURCE`, `PORT`) and `awg-restart.conf` and `awg-watchdog.conf`
(`TUNNELS` or `RULE`) are required for those. The optional `AWG_RESTART_HOOK` in
`common.conf` runs as `<hook> pre <tun>` before every AmneziaWG restart and
`<hook> post <tun>` after it. The files are sourced as shell, often by
root: keep them owned by root and not writable by others.

## Why the watchdogs run as the user

Root cannot append to another user's file in the sticky `/var/mail` directory
when `fs.protected_regular=1`. So the units run with `User=<user>`, and the
few that need root write the letter through `runuser -u <user> -- tee -a`.

## Install

Run `sudo ./install.sh <user>`. It copies the files below, puts the user name
in place of `@USER@` in the units, sudoers and tmpfiles files, and creates
`/etc/watchdogs/common.conf` if it is missing. It never overwrites a
`/etc/watchdogs/*.conf`, does not install the drop-ins and enables nothing.

| File | Destination |
|---|---|
| `watchdog-lib.sh` | `/usr/local/lib/watchdog.sh` |
| `notify-failure.sh`, `watchdog-*.sh` | `/usr/local/bin/<name without .sh>` |
| `clamav-pacman-scan.sh` | `/usr/local/bin/clamav-pacman-scan.sh` |
| `awg-restart.sh` | `/etc/NetworkManager/dispatcher.d/99-awg-restart` |
| system `*.service`, `*.timer` | `/etc/systemd/system/` |
| `notify-failure-user@.service`, `watchdog-clipboard.service`, `watchdog-hyprland.service`, `watchdog-mic-volume.service` | `~/.config/systemd/user/` (the first one as `notify-failure@.service`) |
| `drop-ins/system-<svc>.conf` (by hand) | `/etc/systemd/system/<svc>.service.d/watchdog-notify.conf` |
| `drop-ins/user-<svc>.conf` (by hand) | `~/.config/systemd/user/<svc>.service.d/watchdog-notify.conf` |
| `watchdog-btrfs-sudoers` | `/etc/sudoers.d/watchdog-btrfs` |
| `watchdog-rate.conf` | `/etc/tmpfiles.d/watchdog-rate.conf` |

Then add the settings you need to `/etc/watchdogs/`, copy the drop-ins for the
services you want to watch, run `systemctl --user daemon-reload` as the user
and enable the timers and services.

Test the failure path:

```sh
sudo systemctl start notify-failure@gdm.service
mail
```

## License

MIT
