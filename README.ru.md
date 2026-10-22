[English version](README.md)

# watchdogs

Небольшие сторожа на systemd для десктопа на Arch Linux. Когда что-то
ломается, они кладут письмо в локальный почтовый ящик (`/var/mail/<user>`,
читается командой `mail`) и показывают уведомление на рабочем столе. Почтового
сервера нет, с машины ничего не уходит.

Это мои личные инструменты. Используйте и меняйте их как угодно, но
универсальными они не задумывались: список сервисов и часть проверок подходят
только моей машине. Прочитайте скрипт, прежде чем копировать.

Теперь их немного проще взять себе. Имя пользователя, точки монтирования и
другие настройки лежат не в скриптах, а в `/etc/watchdogs/*.conf`, а файлы
по местам раскладывает `install.sh`.

## Что отслеживается

| Часть | Как запускается | Что делает |
|---|---|---|
| `notify-failure` | drop-in с `OnFailure=` из `drop-ins/` | Юнит упал: письмо с `systemctl status` и последними 30 строками журнала |
| `watchdog-failed-digest` | таймер раз в день | Список упавших системных и пользовательских юнитов, только если он изменился |
| `watchdog-oom` | сервис, опрос раз в 60 с | Письмо на каждое срабатывание OOM: процесс, PID, память, cgroup, кто вызвал |
| `watchdog-disk` | таймер в 08:00, 14:00, 20:00 | Файловая система перешла 90%, дальше письмо на каждые 2 пункта роста |
| `watchdog-btrfs` | таймер раз в неделю | Счётчики ошибок устройств BTRFS и итоги scrub, состояние ext4; пишет только при проблеме |
| `watchdog-btrfs-space` | таймер раз в день, от root | Нераспределённое место на BTRFS упало ниже max(5%, 10 ГиБ): запускает ступенчатый balance данных. Ничего не удаляет; если balance не помог, пишет, чем занят диск |
| `watchdog-clock` | таймер раз в день | Последняя синхронизация NTP старше 7 дней: уведомление запустить `sync-time`. Читает только журнал, в сеть ничего не шлёт |
| `watchdog-ssh` | сервис, работает, пока запущен sshd, опрос раз в 60 с | Письмо на каждый успешный вход по SSH, тревога при 10 неудачных попытках за минуту |
| `watchdog-clipboard` | пользовательский сервис | Перезапускает упавшие демоны буфера обмена `wl-paste`; пишет, только если перезапуск не помог |
| `watchdog-hyprland` | пользовательский сервис | Появился отчёт о падении Hyprland или coredump. Обычный выход из сессии падением не считается |
| `watchdog-mic-volume` | пользовательский сервис | Держит громкость встроенного микрофона веб-камеры на 50% и показывает уведомление при каждом сбросе. WirePlumber сбрасывает её на 100% при подключении и отключении Bluetooth-наушников. Микрофон в разъёме не трогает |
| `clamav-pacman-scan.sh` | хук pacman | После установки проверяет сторонние пакеты (AUR) через ClamAV |
| `watchdog-awg` | таймер каждые 10 с, root | Пингует через каждый поднятый туннель AmneziaWG. Туннель без данных (UDP-поток, замороженный ТСПУ) перезапускает ради нового порта источника; пока туннель лежит, следующий рестарт ждёт 30 с, вдвое дольше каждый раз, до 5 мин. Уведомляет о каждом восстановлении; после 3 неудачных рестартов ещё и письмо |
| `awg-restart.sh` | диспетчер NetworkManager | Когда поднялся внешний интерфейс, перезапускает туннели AmneziaWG без трафика, до 5 попыток |

Общий код лежит в `watchdog-lib.sh`: запись письма, уведомление на рабочем
столе и ограничение частоты. `notify-failure` и `watchdog-clipboard` отправляют
одно и то же событие не чаще раза в 5 минут. Отметки хранятся в
`/run/watchdog-rate`, этот каталог создаёт `watchdog-rate.conf` через tmpfiles.d.

Пока система выключается или стоит в режиме обслуживания, `notify-failure`
молчит, чтобы выключение не завалило ящик письмами.

`AUTO_RESTART` в `/etc/watchdogs/notify-failure.conf`, `clipboard.conf` и
`hyprland.conf` включает и выключает автоматический перезапуск.

## Настройки

Значения по умолчанию записаны в начале каждого скрипта. Файл
`/etc/watchdogs/<имя>.conf` их переопределяет; настройки каждого сторожа
перечислены в `examples/<имя>.conf.example`. `common.conf` с `WATCHDOG_USER`
нужен всем. Для `mic-volume` обязателен `mic-volume.conf` (`SOURCE`, `PORT`),
для `awg-restart` и `watchdog-awg` — `awg-restart.conf` и `awg-watchdog.conf` (`TUNNELS` или `RULE`). Файлы
выполняются как shell, часто от root: владелец — root, запись другим запрещена.

## Почему сторожа работают от пользователя

При `fs.protected_regular=1` root не может дописать в чужой файл внутри
каталога `/var/mail` со sticky-битом. Поэтому юниты запускаются с
`User=<user>`, а те немногие, кому нужен root, пишут письмо через
`runuser -u <user> -- tee -a`.

## Установка

Запустите `sudo ./install.sh <user>`. Он копирует файлы из таблицы, подставляет
имя пользователя вместо `@USER@` в юниты, sudoers и tmpfiles и создаёт
`/etc/watchdogs/common.conf`, если его нет. Существующие `/etc/watchdogs/*.conf`
он не трогает, drop-in'ы не ставит и ничего не включает.

| Файл | Куда |
|---|---|
| `watchdog-lib.sh` | `/usr/local/lib/watchdog.sh` |
| `notify-failure.sh`, `watchdog-*.sh` | `/usr/local/bin/<имя без .sh>` |
| `clamav-pacman-scan.sh` | `/usr/local/bin/clamav-pacman-scan.sh` |
| `awg-restart.sh` | `/etc/NetworkManager/dispatcher.d/99-awg-restart` |
| системные `*.service`, `*.timer` | `/etc/systemd/system/` |
| `notify-failure-user@.service`, `watchdog-clipboard.service`, `watchdog-hyprland.service`, `watchdog-mic-volume.service` | `~/.config/systemd/user/` (первый под именем `notify-failure@.service`) |
| `drop-ins/system-<svc>.conf` (руками) | `/etc/systemd/system/<svc>.service.d/watchdog-notify.conf` |
| `drop-ins/user-<svc>.conf` (руками) | `~/.config/systemd/user/<svc>.service.d/watchdog-notify.conf` |
| `watchdog-btrfs-sudoers` | `/etc/sudoers.d/watchdog-btrfs` |
| `watchdog-rate.conf` | `/etc/tmpfiles.d/watchdog-rate.conf` |

Потом положите нужные настройки в `/etc/watchdogs/`, скопируйте drop-in'ы для
сервисов, за которыми нужно следить, выполните `systemctl --user daemon-reload`
от пользователя и включите таймеры и сервисы.

Проверка пути отказа:

```sh
sudo systemctl start notify-failure@gdm.service
mail
```

## Лицензия

MIT
