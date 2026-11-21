<img width="1534" height="1025" alt="image" src="https://github.com/user-attachments/assets/31818e6c-e7f1-4748-aad7-9d69f55429d9" />


# RKN Watcher v3.2.1

RKN Watcher — набор скриптов для Linux-серверов Debian/Ubuntu, который:

- загружает и обновляет списки `TSPUBLOCK` и `GOVIPS`;
- применяет блокировку через `iptables` + `ipset`;
- умеет фильтровать доступ по странам, allow/deny IP и портам;
- выполняет атомарное обновление списков без потери рабочего набора при сетевой ошибке;
- использует `systemd timer` вместо связки `cron + daemon polling`.

## Главное в версии v3.2.1

- **модульная структура**: вместо монолита на 2050 строк — `lib/*.sh`, точка входа 16 строк;
- **IPv6 для allow/deny-списков**: адреса разделяются по семействам и применяются
  в `ip6tables` (наборы `*6`, цепочка `RKN_GEOIP_HOOK6`);
- **выбор netfilter-бэкенда** (`NETFILTER_BACKEND=auto|legacy|nft`) и его проверка в `doctor`;
- **ротация снапшотов по возрасту** (`SNAPSHOT_MAX_AGE_DAYS`, `SNAPSHOT_KEEP`) и команда
  `rkn-watcher snapshots`.

## Главное в версии v3.2

Аудит v3.1 выявил четыре содержательные ошибки — они исправлены:

- **fail-open в bash**: `ENABLE_TSPUBLOCK="true"` / `"1"` / `"on"` больше не выключают блокировку молча; некорректное значение — явная ошибка (`normalize_bool`);
- **самоблок при включении GeoIP**: в `RKN_GEOIP_HOOK` добавлены `-i lo -j RETURN` и `-m conntrack --ctstate ESTABLISHED,RELATED -j RETURN`; появилась команда `rkn-watcher allow-my-ip` и запрос «добавить мой SSH-IP» при включении GeoIP;
- **allow/deny-порты теперь работают всегда**: блокировки вынесены в отдельную стадию `RKN_DENY`, которая не зависит от `FILTER_PORTS`;
- **правила применяются атомарно** через один `iptables-restore` вместо серии `iptables -A` (нет гонок с xtables lock, нет полуприменённого состояния).

Дополнительно:

- `install`/`update` из `/usr/local/bin/rkn-watcher` починен (`readlink -f` + поиск helper-файлов в `$INSTALL_DIR`);
- `shopt -s inherit_errexit`: сбой `ipset restore/swap` больше не маскируется как успешное обновление;
- IPv6-блокировка (`TSPUIPS6`, `GOVIPS6`, цепочки `TSPUBLOCK6`/`GOVBLOCK6`), если в системе есть `ip6tables`;
- `PORT_POLICY=strict` — открыты только порты из `FILTER_PORTS`;
- sanity-гейт списков: подозрительное уменьшение/рост источника не применяется (`RKN_ALLOW_LIST_SHRINK=1` для осознанного обхода);
- условный GET (`curl -z`) и сигнатуры наборов — неизменные списки не перезаливаются;
- новые команды: `doctor`, `metrics`, `status --json`, `apply --dry-run`, `snapshot`, `rollback`, `allow-my-ip`, `block-ip`, `unblock-ip`;
- logrotate-конфиг, `RandomizedDelaySec` в таймере, hardening в systemd-юнитах, бэкап конфигурации перед обновлением;
- CI проверяет `shellcheck`, `sha256sum -c` и прогоняет тесты, включая регрессии на найденные баги.

## Состав репозитория

```text
RKN-Watcher/
├── installer.sh
├── release.sh
├── rkn-watcher.sh          # точка входа (16 строк)
├── lib/
│   ├── config.sh           # пути, константы, загрузка модулей
│   ├── common.sh           # вывод, логи, настройки, валидация
│   ├── firewall.sh         # ipset, правила RST, netfilter-бэкенды
│   ├── snapshots.sh        # снапшоты и откат
│   ├── lists.sh            # загрузка и применение блок-листов
│   ├── services.sh         # systemd, logrotate, install/uninstall
│   ├── ui.sh               # статус, doctor, меню
│   └── cli.sh              # разбор аргументов и main()
├── config_tool.py
├── geoip_apply.py
├── README.ru.md / README.en.md
├── CHANGELOG.ru.md / CHANGELOG.en.md
├── RELEASE_NOTES.ru.md / RELEASE_NOTES.en.md
├── PUBLISHING.ru.md / PUBLISHING.en.md
├── docs/
│   ├── ru/
│   └── en/
└── tests/
```

## Быстрый старт

```bash
git clone https://github.com/Balbuto/RKN-Watcher.git
cd RKN-Watcher
chmod +x installer.sh rkn-watcher.sh
sudo ./installer.sh
```

Установщик:
- проверяет запуск от `root`;
- проверяет зависимости;
- устанавливает отсутствующие пакеты;
- запускает основной интерактивный процесс установки;
- умеет выполнять полное удаление внесённых изменений.

## Основные команды

### Через установщик
```bash
sudo ./installer.sh
sudo ./installer.sh install
sudo ./installer.sh uninstall
sudo ./installer.sh deps
sudo ./installer.sh status
```

### Через основной скрипт
```bash
sudo ./rkn-watcher.sh install
sudo ./rkn-watcher.sh update
sudo ./rkn-watcher.sh apply
sudo ./rkn-watcher.sh apply --dry-run      # показать правила без применения
sudo ./rkn-watcher.sh status               # --json для машинного вывода
sudo ./rkn-watcher.sh doctor               # диагностика окружения и правил
sudo ./rkn-watcher.sh metrics              # метрики Prometheus
sudo ./rkn-watcher.sh allow-my-ip          # разрешить свой текущий SSH-IP
sudo ./rkn-watcher.sh snapshot            # снапшот правил
sudo ./rkn-watcher.sh snapshots           # список снапшотов
sudo ./rkn-watcher.sh rollback            # откат к последнему снапшоту
sudo ./rkn-watcher.sh uninstall
```

После установки также создаётся команда:

```bash
sudo rkn-watcher
```

## Поддерживаемая среда

- Debian 11 / 12
- Ubuntu 20.04 / 22.04 / 24.04
- IPv4 и IPv6 (IPv6 включается автоматически при наличии `ip6tables`)
- netfilter-бэкенды `legacy` и `nft` (выбор через `NETFILTER_BACKEND`)
- Требуются права `root`

## Что важно знать про v3.2.1

- **Модули.** Скрипт состоит из точки входа и каталога `lib/`. При обновлении
  вручную копируйте `lib/` целиком; `installer.sh` и `rkn-watcher install` делают это сами.
- **IPv6.** Allow/deny-адреса и CIDR принимаются в обеих версиях протокола и
  применяются в `ip6tables`; без `ip6tables` IPv6-часть пропускается с предупреждением.
- **Бэкенд.** Если в системе есть и `iptables-legacy`, и `iptables-nft`, задайте
  нужный явно и проверьте `sudo rkn-watcher doctor | grep -i backend`.
- **nftables.** Установщик проверяет пакет `nftables`, утилиту `nft`, читаемость
  ruleset и показывает, через какой бэкенд работает `iptables`; при проблеме установка
  останавливается. Отдельно: `sudo ./installer.sh nft`.
- **Снапшоты.** Хранятся последние `SNAPSHOT_KEEP` (10) и всё не старше
  `SNAPSHOT_MAX_AGE_DAYS` (30 дней). Откат — `sudo rkn-watcher rollback`.

## Источники данных

- TSPU / Skipa CIDR: `https://github.com/tread-lightly/CyberOK_Skipa_ips`
- GOVIPS / blacklist-v4.ipset: `https://github.com/C24Be/AS_Network_List`
- Country CIDR: `https://www.ipdeny.com/ipblocks/`

Источники сторонние и не подписаны — это известное ограничение (см.
[Безопасность](docs/ru/SECURITY.md)); частично компенсируется sanity-гейтом списков.

## Документация

- [Установка](docs/ru/INSTALL.md)
- [Интерактивный установщик](docs/ru/INSTALLER.md)
- [Использование](docs/ru/USAGE.md)
- [Конфигурация](docs/ru/CONFIGURATION.md)
- [Миграция](docs/ru/MIGRATION.md)
- [Решение проблем](docs/ru/TROUBLESHOOTING.md)
- [Безопасность](docs/ru/SECURITY.md)

## Лицензия

MIT. См. файл [LICENSE](LICENSE).
