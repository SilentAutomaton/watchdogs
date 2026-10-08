[Русская версия](README.ru.md)

# watchdogs

Small systemd watchdogs for an Arch Linux desktop. When something breaks, they
put a letter in the local mailbox (`/var/mail/<user>`, read with `mail`) and show
a desktop notification. There is no mail server and nothing leaves the machine.

These are my personal tools. You are free to use them and change them however
you like, but they are not meant to be universal: the user name, mount points
and the list of watched services are set inside the scripts. Read a script
before you copy it.

## What is watched

| Piece | How it runs | What it does |
|---|---|---|
| `notify-failure` | `OnFailure=` drop-ins in `drop-ins/` | A unit failed: mails `systemctl status` and the last 30 journal lines |
| `watchdog-failed-digest` | daily timer | Mails the list of failed system and user units, only when the list changed |
| `watchdog-oom` | service, polls every 60 s | One letter per OOM kill: process, PID, memory, cgroup, who triggered it |
| `watchdog-disk` | timer, 08:00, 14:00, 20:00 | A filesystem crossed 90%, then again for every 2 more points |
| `watchdog-btrfs` | weekly timer | BTRFS device error counters and scrub results, ext4 state; mails only on a problem |
| `watchdog-btrfs-space` | daily timer, root | Unallocated BTRFS space fell below max(5%, 10 GiB): runs a stepwise data balance. Never deletes anything; if balance does not help, mails what fills the disk |
| `watchdog-ssh` | service, polls every 60 s | A letter for every successful SSH login, an alert at 10 failed attempts in a minute |
| `watchdog-clipboard` | user service | Restarts dead `wl-paste` clipboard daemons; mails only if the restart fails |
| `watchdog-hyprland` | user service | A Hyprland crash report or coredump appeared. A normal logout is not a crash |
| `clamav-pacman-scan.sh` | pacman hook | Scans foreign (AUR) packages after install with ClamAV |
| `awg-restart.sh` | NetworkManager dispatcher | When a network comes up, restarts the AmneziaWG tunnels that were up, up to 5 tries |

Shared code lives in `watchdog-lib.sh`: the mail writer, the desktop
notification and a rate limit. `notify-failure` and `watchdog-clipboard` send
the same event at most once in 5 minutes. The stamps live in `/run/watchdog-rate`,
which `watchdog-rate.conf` creates through tmpfiles.d.

`notify-failure` stays silent while the system is stopping or in maintenance
mode, so a shutdown does not flood the mailbox.

`AUTO_RESTART` at the top of `notify-failure.sh`, `watchdog-clipboard.sh` and
`watchdog-hyprland.sh` turns automatic restarts on or off.

## Why the watchdogs run as the user

Root cannot append to another user's file in the sticky `/var/mail` directory
when `fs.protected_regular=1`. So the units run with `User=<user>`, and the
few that need root write the letter through `runuser -u <user> -- tee -a`.

## Install

There is no installer. Copy each file to its place by hand:

| File | Destination |
|---|---|
| `watchdog-lib.sh` | `/usr/local/lib/watchdog.sh` |
| `notify-failure.sh`, `watchdog-*.sh` | `/usr/local/bin/<name without .sh>` |
| `clamav-pacman-scan.sh` | `/usr/local/bin/clamav-pacman-scan.sh` |
| `awg-restart.sh` | `/etc/NetworkManager/dispatcher.d/99-awg-restart` |
| system `*.service`, `*.timer` | `/etc/systemd/system/` |
| `notify-failure-user@.service`, `watchdog-clipboard.service`, `watchdog-hyprland.service` | `~/.config/systemd/user/` (the first one as `notify-failure@.service`) |
| `drop-ins/system-<svc>.conf` | `/etc/systemd/system/<svc>.service.d/watchdog-notify.conf` |
| `drop-ins/user-<svc>.conf` | `~/.config/systemd/user/<svc>.service.d/watchdog-notify.conf` |
| `watchdog-btrfs-sudoers` | `/etc/sudoers.d/watchdog-btrfs` |
| `watchdog-rate.conf` | `/etc/tmpfiles.d/watchdog-rate.conf` |

Then replace the user name in the scripts and units with yours, run
`systemctl daemon-reload` for both scopes and enable the timers and services.

Test the failure path:

```sh
sudo systemctl start notify-failure@gdm.service
mail
```

## License

MIT
