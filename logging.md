# System Logging

## Primary log store: systemd journal

All systemd services write here by default.

```
journalctl -u <service>        # logs for one service
journalctl -b                  # current boot
journalctl -b -1               # previous boot
journalctl --since "1 hour ago"
journalctl -p err              # errors only
```

**Config:** `/etc/systemd/journald.conf.d/limits.conf`
```ini
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=3month
```
Default `/etc/systemd/journald.conf` — все параметры закомментированы, лимиты берутся из drop-in.
Rotation: journald ротирует сам при достижении лимита.

---

## /var/log — файловые логи

| Файл/директория          | Размер   | Что                        | Ротация               |
|--------------------------|----------|----------------------------|-----------------------|
| `pacman.log`             | ~2.4 МБ  | История пакетов pacman     | нет (растёт)          |
| `snapper.log`            | ~3.2 МБ  | Снапшоты BTRFS             | logrotate monthly×3   |
| `awg-restart.log`        | ~2.3 МБ  | Перезапуски AmneziaVPN/AWG | logrotate weekly×4    |
| `opensnitchd.log`        | ~952 КБ  | Файрвол opensnitch         | logrotate weekly×7 (пакетный) |
| `boot.log`               | ~1.2 МБ  | Загрузка systemd-boot      | нет                   |
| `auto-cpufreq.log`       | 0 байт   | CPU governor               | —                     |
| `haskell-register.log`   | ~1.0 МБ  | haskell пакеты             | нет                   |
| `audit/`                 | ?        | auditd (требует sudo)      | встроенная: 8 МБ × 5  |
| `samba/`                 | мелкие   | smbd/nmbd                  | logrotate (пакетный)  |
| `httpd/`                 | пусто    | Apache — сервис disabled   | logrotate (пакетный)  |
| `gitea/`                 | есть     | Gitea                      | неизвестно            |
| `i2pd/`                  | есть     | I2P daemon                 | неизвестно            |
| `clamav/`                | есть     | ClamAV antivirus           | logrotate (пакетный)  |
| `gdm/`                   | есть     | GNOME Display Manager      | —                     |

---

## logrotate

**Установлен:** logrotate-3.22.0  
**Таймер:** `logrotate.timer` (enabled, запускается daily)

```
systemctl status logrotate.timer
systemctl list-timers logrotate.timer
sudo logrotate -d /etc/logrotate.d/<name>   # dry-run
sudo logrotate -f /etc/logrotate.d/<name>   # принудительно
```

**Конфиги в `/etc/logrotate.d/`:**

| Файл              | Лог                          | Политика        |
|-------------------|------------------------------|-----------------|
| `awg-restart`     | `/var/log/awg-restart.log`   | weekly, 4 weeks |
| `snapper`         | `/var/log/snapper.log`       | monthly, 3 mon  |
| `opensnitch`      | `/var/log/opensnitchd.log`   | пакетный: weekly, 7 weeks, maxsize 50M |
| `clamav`          | пакетный                     | —               |
| `samba`           | пакетный                     | —               |
| `httpd`           | пакетный                     | —               |
| `lirc`            | пакетный                     | —               |

---

## auditd

**Config:** `/etc/audit/auditd.conf`  
- `max_log_file = 8` МБ  
- `num_logs = 5`  
- `max_log_file_action = ROTATE`

Читать: `sudo ausearch -m all` или `sudo aureport`

---

## Сервисы без файлового логирования (только journal)

- docker / containerd
- NetworkManager
- bluetooth
- unbound (DNS resolver)
- ollama
- AmneziaVPN / wg-quick
- wpa_supplicant
- GDM, polkit, udisks2

---

## Что НЕ настроено / требует внимания

- `pacman.log` — нет ротации, растёт исторически. Добавить `/etc/logrotate.d/pacman` при необходимости.
- `boot.log` — нет ротации.
- `haskell-register.log` — разовый лог установки, можно удалить вручную.
- `gitea/` и `i2pd/` — неизвестна встроенная ротация, стоит проверить конфиги сервисов.
- httpd (Apache) — disabled, лог пуст. Если запустить — лог появится автоматически.

---

## Watchdogs — уведомления о сбоях

Критические компоненты мониторятся через systemd `OnFailure=` и отправляют письма в `/var/mail/silent`.

Читать почту: `mail`  
Счётчик непрочитанных — отображается при открытии терминала (после fortune).  
Все watchdog-и дополнительно шлют системное уведомление (`notify-send`) с кратким описанием проблемы. Логи — только в mail.

### Мониторируемые сервисы

**Системные** (system scope, `OnFailure=notify-failure@%p.service`):

| Сервис | Drop-in |
|--------|---------|
| `gdm.service` | `/etc/systemd/system/gdm.service.d/watchdog-notify.conf` |
| `NetworkManager.service` | `/etc/systemd/system/NetworkManager.service.d/watchdog-notify.conf` |
| `bluetooth.service` | `/etc/systemd/system/bluetooth.service.d/watchdog-notify.conf` |
| `unbound.service` | `/etc/systemd/system/unbound.service.d/watchdog-notify.conf` |
| `docker.service` | `/etc/systemd/system/docker.service.d/watchdog-notify.conf` |
| `ollama.service` | `/etc/systemd/system/ollama.service.d/watchdog-notify.conf` |

**Пользовательские** (user scope, `OnFailure=notify-failure@%p.service`):

| Сервис | Drop-in |
|--------|---------|
| `pipewire.service` | `~/.config/systemd/user/pipewire.service.d/watchdog-notify.conf` |
| `pipewire-pulse.service` | `~/.config/systemd/user/pipewire-pulse.service.d/watchdog-notify.conf` |
| `wireplumber.service` | `~/.config/systemd/user/wireplumber.service.d/watchdog-notify.conf` |
| `easyeffects.service` | `~/.config/systemd/user/easyeffects.service.d/watchdog-notify.conf` |

Письмо содержит: `systemctl status` (exit-код, сигнал, время) + последние 30 строк журнала.

**Clipboard** (отдельный watchdog, т.к. `wl-paste` — не systemd-сервис):

```
systemctl --user status watchdog-clipboard.service
```

Проверяет каждые 30 с: `wl-paste --type text` и `wl-paste --type image`.  
При исчезновении — пытается перезапустить (сохраняет cmdline при старте). Удачный перезапуск пишется только в журнал, письмо приходит, если перезапуск не помог.  
`AUTO_RESTART=true` в `watchdog-clipboard.sh` — отключить можно там же.

### ClamAV — уведомления при нахождении угроз

Pacman hook запускает `/usr/local/bin/clamav-pacman-scan.sh` после каждой установки/обновления.  
При нахождении угрозы: пишет в journal (`systemd-cat -t clamav-pacman`) **и** отправляет письмо в `/var/mail/silent`.

Скрипт: `clamav-pacman-scan.sh` → `/usr/local/bin/clamav-pacman-scan.sh` (копия). Сканирует только пакеты не из репозиториев (`pacman -Qqm`).

### Дополнительные watchdog-сервисы

| Сервис | Тип | Что делает |
|--------|-----|------------|
| `watchdog-failed-digest` | system timer, daily | Шлёт, только если набор упавших юнитов изменился (`/var/lib/watchdog-failed-digest`). Имена юнитов в теме; на каждый юнит Result/ExecMainStatus/время + 10 строк журнала |
| `watchdog-oom` | system service, poll 60s | Одно письмо на событие: имя/PID/RSS (anon+file+shmem в GiB), cgroup, кто вызвал OOM; курсор в `/var/lib/watchdog-oom` |
| `watchdog-disk` | system timer, 08/14/20 | Тема `disk: / 94%; /home 91%`; шлёт при первом пересечении 90% и дальше при росте на 2 пункта; последний процент в `/var/lib/watchdog-disk` |
| `watchdog-hyprland` | user service | Крэш = новый `~/.cache/hyprland/hyprlandCrashReport*.txt` или coredump; выход из сессии письма не шлёт. В письме начало отчёта и user-журнал за 60 с |
| `watchdog-btrfs` | system timer, Sun 09:00 | Только при проблеме: ненулевые device error counters, прерванный scrub, ошибки scrub. `no stats available` (scrub ещё не запускался) — не проблема |
| `watchdog-ssh` | system service, poll 60s | Письмо на каждый успешный вход (user/IP/метод); alert при ≥10 failed за 60с; курсор в `/var/lib/watchdog-ssh` |
| `awg-restart` | NM dispatcher, root | На каждый `up` сети перезапускает уже поднятые awg-туннели (до 5 попыток, `ping -I <туннель>`). Список туннелей берёт из `iface.out` правила killswitch `000-vpnonly-allow-claude.json` без `lo`. Письмо и notify на восстановление (с числом попыток) и на провал (не чаще раза в 5 минут); лог `/var/log/awg-restart.log` |

Открытые порты больше не сторожатся письмами: их показывает виджет «Ports» в правой панели Quickshell (`sudo -n ss -tulpnH`, правило в `dots/system/sudoers.d/listening-ports`).

### Конфигурируемый автоперезапуск

Переменная `AUTO_RESTART` есть во всех watchdog-скриптах:

| Скрипт | По умолчанию | Что делает при `true` |
|--------|-------------|----------------------|
| `watchdog-clipboard.sh` | `true` | Перезапускает wl-paste с сохранённым cmdline |
| `notify-failure.sh` | `false` | `systemctl restart <unit>` |
| `watchdog-hyprland.sh` | `false` | Запускает `Hyprland &` (убивает все дочерние процессы) |

### Rate limiting

`notify-failure.sh` и `watchdog-clipboard.sh` не шлют повторно одно событие чаще раза в 5 минут.  
Флаги хранятся в `/run/watchdog-rate/` (tmpfs, сбрасывается при перезагрузке). Каталог создаёт `watchdog-rate.conf` в `/etc/tmpfiles.d/`: сторожа работают от silent и сами создать его в `/run` не могут.

### Защита от ложных срабатываний при выключении

`notify-failure.sh` проверяет `systemctl is-system-running`: при `stopping` или `maintenance` письмо не отправляется.  
`watchdog-clipboard.sh` не проверяет wl-paste, пока нет Hyprland или он запущен меньше минуты назад.

### Файлы в этой директории

```
notify-failure.sh              → /usr/local/bin/notify-failure
watchdog-lib.sh                → /usr/local/lib/watchdog.sh
watchdog-clipboard.sh          → /usr/local/bin/watchdog-clipboard
watchdog-hyprland.sh           → /usr/local/bin/watchdog-hyprland
watchdog-failed-digest.sh      → /usr/local/bin/watchdog-failed-digest
watchdog-oom.sh                → /usr/local/bin/watchdog-oom
watchdog-disk.sh               → /usr/local/bin/watchdog-disk
clamav-pacman-scan.sh          → /usr/local/bin/clamav-pacman-scan.sh
notify-failure@.service        → /etc/systemd/system/notify-failure@.service
watchdog-oom.service           → /etc/systemd/system/watchdog-oom.service
watchdog-failed-digest.service → /etc/systemd/system/watchdog-failed-digest.service
watchdog-failed-digest.timer   → /etc/systemd/system/watchdog-failed-digest.timer
watchdog-disk.service          → /etc/systemd/system/watchdog-disk.service
watchdog-disk.timer            → /etc/systemd/system/watchdog-disk.timer
watchdog-btrfs.sh              → /usr/local/bin/watchdog-btrfs
watchdog-btrfs.service         → /etc/systemd/system/watchdog-btrfs.service
watchdog-btrfs.timer           → /etc/systemd/system/watchdog-btrfs.timer
watchdog-ssh.sh                → /usr/local/bin/watchdog-ssh
awg-restart.sh                 → /etc/NetworkManager/dispatcher.d/99-awg-restart
watchdog-ssh.service           → /etc/systemd/system/watchdog-ssh.service
watchdog-btrfs-sudoers         → /etc/sudoers.d/watchdog-btrfs
drop-ins/system-ollama.conf    → /etc/systemd/system/ollama.service.d/watchdog-notify.conf
notify-failure-user@.service   → ~/.config/systemd/user/notify-failure@.service  (передаёт --user)
watchdog-rate.conf             → /etc/tmpfiles.d/watchdog-rate.conf
watchdog-clipboard.service     → ~/.config/systemd/user/watchdog-clipboard.service
watchdog-hyprland.service      → ~/.config/systemd/user/watchdog-hyprland.service
drop-ins/system-*.conf         → /etc/systemd/system/<svc>.service.d/watchdog-notify.conf
drop-ins/user-*.conf           → ~/.config/systemd/user/<svc>.service.d/watchdog-notify.conf
```

### Тест вручную

```bash
# Имитирует сбой gdm — должно появиться письмо
sudo -A systemctl start notify-failure@gdm.service
mail
```

### Заметки

- `/var/mail/silent` — mbox файл, `mail:silent 660`. Только пользователь `silent` может писать.  
  Root писать в него не может: `fs.protected_regular=1` запрещает root открывать с O_CREAT чужой файл в sticky-каталоге `/var/mail`. Поэтому сторожа работают с `User=silent`, а `send_mail` из `/usr/local/lib/watchdog.sh` под root пишет через `runuser -u silent -- tee -a` (так пишет хук ClamAV).
- s-nail (mailx) установлен для чтения mbox.
- После `mail` + `q` прочитанные письма уходят в `~/mbox`, спул очищается.

---

## Быстрая диагностика

```bash
journalctl --disk-usage                          # размер journal
du -sh /var/log/*/                               # размер файловых логов
sudo logrotate --debug /etc/logrotate.d/*        # проверка конфигов
systemctl list-timers                            # все таймеры и следующий запуск
mail                                             # непрочитанные уведомления watchdog
systemctl list-units --state=failed              # упавшие system-юниты прямо сейчас
systemctl --user list-units --state=failed       # упавшие user-юниты
```
