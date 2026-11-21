# Установка

## Системные требования

Поддерживаемые системы:

- Debian 11 / 12
- Ubuntu 20.04 / 22.04 / 24.04

Требуется:

- root-доступ;
- `systemd`;
- `iptables` + `ipset` + `nftables` (пакеты ставятся установщиком; наличие, доступность
  утилиты `nft` и загруженный ruleset проверяются перед установкой);
- `python3` — для `config_tool.py` и `geoip_apply.py`;
- доступ в интернет для первичной загрузки списков.

Опционально:

- `ip6tables` — включает фильтрацию IPv6 (наборы `TSPUIPS6`, `GOVIPS6`,
  `GEOIP_ALLOW_IPS6` и цепочки `*6`). Без него IPv6-часть просто пропускается,
  IPv4 продолжает работать;
- `iptables-legacy` / `iptables-nft` — если в системе есть оба бэкенда, выбор
  задаётся ключом `NETFILTER_BACKEND` (см. [конфигурацию](CONFIGURATION.md)).

## Рекомендуемый способ

```bash
git clone https://github.com/Balbuto/RKN-Watcher.git
cd RKN-Watcher
chmod +x installer.sh rkn-watcher.sh
sudo ./installer.sh
```

Интерактивный `installer.sh`:

1. проверяет запуск от `root`;
2. проверяет наличие зависимостей (`apt` / `dpkg`);
3. устанавливает отсутствующие пакеты (включая `nftables`);
4. запоминает, какие пакеты поставил именно он;
5. проверяет nftables: пакет, утилита `nft`, читаемость ruleset, через какой бэкенд
   работает `iptables` (подробно — в разделе [«Проверка nftables»](INSTALLER.md));
6. запускает основной процесс установки `rkn-watcher.sh install`.

Основной скрипт затем:

1. создаёт каталоги в `/opt`, `/etc`, `/var/lib`, `/var/log`;
2. копирует `rkn-watcher.sh`, каталог модулей `lib/`, `config_tool.py`,
   `geoip_apply.py` в `/opt/rkn-watcher`;
3. создаёт команду `rkn-watcher` в `/usr/local/bin`;
4. создаёт `systemd`-юниты (boot-восстановление и таймер автообновления);
5. создаёт `settings.conf`, `whitelist.json`, `blacklist.json`;
6. загружает `TSPUBLOCK` и `GOVIPS`;
7. применяет правила `iptables` / `ipset`.

## Что создаётся на системе

### Исполняемые файлы

- `/opt/rkn-watcher/rkn-watcher.sh` — точка входа (16 строк)
- `/opt/rkn-watcher/lib/*.sh` — модули: `config`, `common`, `firewall`, `snapshots`,
  `lists`, `services`, `ui`, `cli`
- `/opt/rkn-watcher/config_tool.py`
- `/opt/rkn-watcher/geoip_apply.py`
- `/usr/local/bin/rkn-watcher` — символическая ссылка на точку входа

### Конфигурация (`0600 root`)

- `/etc/rkn-watcher/settings.conf`
- `/etc/rkn-watcher/whitelist.json`
- `/etc/rkn-watcher/blacklist.json`

### Состояние и кэш

- `/var/lib/rkn-watcher/cache/lists/` — кэш скачанных списков (условный GET)
- `/var/lib/rkn-watcher/cache/countries/` — кэш country-зон ipdeny
- `/var/lib/rkn-watcher/state/` — счётчики и сигнатуры наборов
- `/var/lib/rkn-watcher/snapshots/` — снапшоты правил перед каждым `apply`/`update`
- `/var/lib/rkn-watcher/backups/` — бэкапы `/etc/rkn-watcher` перед обновлением кода
- `/var/lib/rkn-watcher/locks/` — `flock`-файлы

### Логи (с ротацией через logrotate)

- `/var/log/rkn-watcher/update.log`
- `/var/log/rkn-watcher/actions.log`
- `/var/log/rkn-watcher/geoip.log`

### systemd

- `rkn-watcher-boot.service` — восстановление правил при загрузке
- `rkn-watcher-update.service` + `rkn-watcher-update.timer` — автообновление списков

## Первый запуск

```bash
sudo rkn-watcher            # интерактивное меню
sudo rkn-watcher status     # статус
sudo rkn-watcher doctor     # диагностика окружения и правил
```

## Обновление до v3.2.1

```bash
cd RKN-Watcher
git pull
sha256sum -c SHA256SUMS
sudo ./installer.sh install
```

При запросе выберите сохранение текущей конфигурации. Обновление копирует и модули
`lib/`, поэтому отдельно ничего докладывать не нужно. Подробности — в
[миграции](MIGRATION.md).

## Установка без git

Нужно скачать в одну директорию:

- `installer.sh`
- `rkn-watcher.sh`
- `lib/` (все 8 модулей)
- `config_tool.py`
- `geoip_apply.py`

Затем:

```bash
chmod +x installer.sh rkn-watcher.sh
sudo ./installer.sh
```

Если каталога `lib/` нет, скрипт остановится с сообщением
`Не найден каталог модулей lib/` — без модулей точка входа работать не может.

## Удаление

```bash
sudo ./installer.sh uninstall
```

Или:

```bash
sudo rkn-watcher uninstall
```

Удаляются только изменения, управляемые проектом: юниты, управляемые цепочки и наборы
(IPv4 и IPv6), `/opt/rkn-watcher`, `/etc/rkn-watcher`, `/var/lib/rkn-watcher`,
`/var/log/rkn-watcher`, `/usr/local/bin/rkn-watcher`.
