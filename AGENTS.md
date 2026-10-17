# Working on watchdogs

Tier: 1

## What it is

Small bash watchdogs for one Arch Linux desktop: systemd timers, services,
OnFailure drop-ins, a pacman hook and a NetworkManager dispatcher. They write a
letter to `/var/mail/<user>` and show a desktop notification. Settings live in
`/etc/watchdogs/*.conf`; `examples/` holds the templates.

## Running it

```
sudo ./install.sh <user>
```

## Checking it

```
shellcheck -S warning *.sh && sudo systemctl start notify-failure@gdm.service && mail
```

## Code

[`codestyle.md`](codestyle.md), the same standard at every
tier. This project has more than one module, so the modularity rules apply.

## Rules

1. A script never deletes user data and never runs a balance, restart or
   tunnel change that the README does not describe.
2. Nothing personal is committed. No keys, no home paths, no dumps, no user
   names or machine IDs in scripts and units: real values go to
   `/etc/watchdogs/*.conf`, the repository ships `examples/*.conf.example` and
   `@USER@` placeholders only.

## Commits

One step, one commit. A single line of plain English describing what the code
now does. No tool names, no attribution trailers.
