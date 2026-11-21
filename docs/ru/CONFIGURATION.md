# Конфигурация

## settings.conf

Файл:

```text
/etc/rkn-watcher/settings.conf
```

Версия в репозитории: `3.2.1`. Полный список ключей с дефолтами:

```ini
ENABLE_TSPUBLOCK="y"
ENABLE_GOVIPS="y"
FILTER_PORTS="all"
PORT_POLICY="geoip_only"
NETFILTER_BACKEND="auto"
LOG_RST="n"
AUTO_UPDATE="y"
SNAPSHOT_KEEP="10"
SNAPSHOT_MAX_AGE_DAYS="30"
```

Boolean-ключи (`LOG_RST`, `AUTO_UPDATE`, `ENABLE_TSPUBLOCK`, `ENABLE_GOVIPS`)
принимаются в любой распространённой записи: `y/n`, `yes/no`, `true/false`, `1/0`,
`on/off`. Любое другое значение — **ошибка конфигурации**: `apply`/`update`
завершатся с кодом 1 и правила не будут применены (fail-closed).

При дублировании ключа действует **последнее** значение (как в shell), а `doctor`
выводит предупреждение со списком дублирующихся ключей.

### `FILTER_PORTS`

Область действия GeoIP: на какие TCP-порты распространяется фильтр по странам.
Deny/allow-правила (`blacklist.json`/`whitelist.json`) от этого ключа **не зависят**.

```ini
FILTER_PORTS="all"
FILTER_PORTS="443"
FILTER_PORTS="80,443,8443"
```

### `PORT_POLICY`

```ini
PORT_POLICY="geoip_only"   # по умолчанию: GeoIP фильтрует FILTER_PORTS, остальные порты открыты
PORT_POLICY="strict"       # открыты только порты из FILTER_PORTS, всё остальное закрывается
```

`strict` — режим белого списка портов: `-p tcp --dport <port> RETURN` для каждого
порта из `FILTER_PORTS` (TCP и UDP), затем `DROP`.

Если GeoIP включён при `FILTER_PORTS="all"`, `apply` выдаёт предупреждение о риске
потери доступа: фильтр по стране применится ко всем портам, спасут только уже
установленные соединения и allow-список.

### `NETFILTER_BACKEND`

```ini
NETFILTER_BACKEND="auto"     # как настроено в системе (по умолчанию)
NETFILTER_BACKEND="legacy"   # iptables-legacy / ip6tables-legacy
NETFILTER_BACKEND="nft"      # iptables-nft / ip6tables-nft
```

Нужно на серверах, где одновременно есть `legacy`- и `nft`-утилиты (после миграции
дистрибутива, рядом с docker или Kubernetes). Выбор действует и в bash-части
(`iptables`, `ip6tables`, `iptables-restore`…), и в `geoip_apply.py`, и учитывается
при создании снапшотов и откате.

- если выбранного бинаря нет — предупреждение в лог и откат на обычный `iptables`;
- неизвестное значение (`bogus`) — ошибка конфигурации;
- `doctor` печатает заданное и фактическое значение и предупреждает о расхождении;
- `installer.sh` перед установкой проверяет сам `nftables` (пакет, утилита `nft`,
  читаемость ruleset) и сообщает, через какой бэкенд работает `iptables`
  (см. [установщик](INSTALLER.md)).

### `SNAPSHOT_KEEP` и `SNAPSHOT_MAX_AGE_DAYS`

```ini
SNAPSHOT_KEEP="10"           # столько последних снапшотов не удаляется никогда
SNAPSHOT_MAX_AGE_DAYS="30"   # всё старше 30 дней удаляется
```

Снапшот создаётся перед каждым `apply`/`update` и вручную командой `snapshot`
(`iptables-save`, `ip6tables-save`, `ipset save`) в
`/var/lib/rkn-watcher/snapshots/<timestamp>/`. Список — `rkn-watcher snapshots`.

### `LOG_RST`

Включает/выключает логирование RST-блокировок для `TSPUBLOCK` и `GOVIPS`.

```ini
LOG_RST="y"
LOG_RST="n"
```

Заблокированные пакеты попадают в системный лог ядра (`LOG`-таргет с
`--log-prefix "TSPUBLOCK: "` / `"GOVIPS: "`), смотреть так:

```bash
sudo dmesg -T | grep -E 'TSPUBLOCK|GOVIPS'
sudo journalctl -k | grep -E 'TSPUBLOCK|GOVIPS'
```

Частота ограничена: `-m limit --limit 5/min --limit-burst 10`.

### `AUTO_UPDATE`

Включает/выключает `systemd timer` `rkn-watcher-update.timer`.

### `ENABLE_TSPUBLOCK` / `ENABLE_GOVIPS`

Включает/выключает соответствующий блок-лист (`TSPUBLOCK` / `GOVIPS`).

## whitelist.json

```text
/etc/rkn-watcher/whitelist.json
```

```json
{
  "enabled": true,
  "countries": ["RU", "FI"],
  "ips": ["1.2.3.4", "10.0.0.0/24", "2001:db8::/32"],
  "ports": [22, 443]
}
```

Поля:

- `enabled` — включён ли GeoIP (JSON-boolean);
- `countries` — коды разрешённых стран (ISO-3166 alpha-2, верхний регистр);
- `ips` — разрешённые адреса/CIDR: **IPv4 и IPv6**;
- `ports` — разрешённые TCP-порты.

`enabled` должен быть JSON-boolean: `true` или `false`. Для совместимости helper
читает и распространённые legacy-значения (`"true"`, `"false"`, `1`, `0`), но всегда
записывает JSON-boolean.

Адреса разделяются по семействам автоматически: IPv4 → `GEOIP_ALLOW_IPS`,
IPv6 → `GEOIP_ALLOW_IPS6` (`family inet6`). Некорректная запись (`2001:db8:::1`)
— ошибка конфигурации, а не тихий пропуск.

## blacklist.json

```text
/etc/rkn-watcher/blacklist.json
```

```json
{
  "ips": ["203.0.113.5", "198.51.100.0/24", "2001:db8:dead::/48"],
  "ports": [25, 3389]
}
```

Поля:

- `ips` — запрещённые адреса/CIDR (IPv4 и IPv6 → `GEOIP_DENY_IPS`, `GEOIP_DENY_IPS6`);
- `ports` — запрещённые TCP-порты.

## Порядок применения правил

IPv4: `INPUT → RKN_GEOIP_HOOK` (комментарий `rkn-watcher-geoip-hook`),
плюс хуки `-j TSPUBLOCK` и `-j GOVBLOCK`.

Внутри `RKN_GEOIP_HOOK`:

1. `-i lo` → `RETURN` — локальный трафик не фильтруется;
2. `-m conntrack --ctstate ESTABLISHED,RELATED` → `RETURN` — установленные сессии
   (в том числе ваша SSH-сессия) не рвутся при применении правил;
3. `RKN_DENY` — **не зависит от `FILTER_PORTS`**:
   1. deny IP/CIDR → `DROP`
   2. deny ports → `DROP`
4. `GEOIP_DROP` — только для портов из `FILTER_PORTS` (при `geoip_only`):
   1. allow IP/CIDR → `RETURN`
   2. allow ports → `RETURN`
   3. allow countries → `RETURN`
   4. всё остальное → `DROP`
5. `RKN_PROTECT` — только при `PORT_POLICY=strict`: всё, что не входит
   в `FILTER_PORTS` → `DROP`.

Если список стран пуст, country-based drop не применяется и стадия завершится `RETURN`.

Вся цепочка собирается в один `iptables-restore`-файл и применяется атомарно:
`apply --dry-run` распечатает ровно тот набор правил, который будет применён.

## IPv6

| Что | Наборы | Цепочки (`ip6tables`) |
|---|---|---|
| Блокировка RST от ТСПУ | `TSPUIPS6` | `TSPUBLOCK6` |
| GOVIPS | `GOVIPS6` | `GOVBLOCK6` |
| allow IP | `GEOIP_ALLOW_IPS6` | `RKN_GEOIP_HOOK6` |
| deny IP | `GEOIP_DENY_IPS6` | `RKN_DENY` (внутри хука) |
| страны | `GEOIP_COUNTRIES_ALLOW6` | `GEOIP_DROP` (внутри хука) |

Логика внутри `RKN_GEOIP_HOOK6` та же, что для IPv4 (`lo`, `ESTABLISHED,RELATED`,
deny, allow, страны, strict-политика на портах). Хук создаётся, если есть хотя бы одна
IPv6-стадия: allow/deny-список, страновой фильтр или `PORT_POLICY=strict`.

Если `ip6tables` в системе нет, IPv6-часть пропускается с предупреждением, IPv4
продолжает работать. Проверка: `sudo rkn-watcher doctor` и
`sudo ip6tables -L RKN_GEOIP_HOOK6 -v -n`.

## Файлы состояния

```text
/var/lib/rkn-watcher/state/tspu_count.txt   # сколько записей было в последнем удачном обновлении
/var/lib/rkn-watcher/state/gov_count.txt
/var/lib/rkn-watcher/state/sig.*            # сигнатуры наборов (в т.ч. *.ips6, *.countries)
/var/lib/rkn-watcher/snapshots/<stamp>/     # iptables-save + ip6tables-save + ipset save
/var/lib/rkn-watcher/cache/lists/           # кэш скачанных списков (условный GET по -z)
/var/lib/rkn-watcher/cache/countries/       # кэш country-зон ipdeny
/var/lib/rkn-watcher/backups/               # бэкапы /etc/rkn-watcher перед обновлением кода
```

## Sanity-проверка списков

Перед применением нового набора проверяется, что он не «схлопнулся» и не вырос
аномально: если новых записей меньше 50% или больше 500% от предыдущего значения,
обновление **не применяется** (старый набор продолжает работать), в `update.log`
пишется причина. Осознанный обход:

```bash
sudo RKN_ALLOW_LIST_SHRINK=1 rkn-watcher update
```

## Безопасное редактирование helper-утилитой

`config_tool.py` удерживает один advisory lock на весь цикл чтения, изменения и записи.
Используйте его вместо одновременных ручных правок, если конфигурацией управляют
несколько администраторов или задач автоматизации.

```bash
sudo /opt/rkn-watcher/config_tool.py add-country FI
sudo /opt/rkn-watcher/config_tool.py remove-country FI
sudo /opt/rkn-watcher/config_tool.py add-ip 1.2.3.4
sudo /opt/rkn-watcher/config_tool.py add-ip 2001:db8::1     # IPv6 тоже принимается
sudo /opt/rkn-watcher/config_tool.py add-port 443
sudo /opt/rkn-watcher/config_tool.py add-deny-ip 203.0.113.5
sudo /opt/rkn-watcher/config_tool.py add-deny-port 25
sudo /opt/rkn-watcher/config_tool.py show all
```

После ручного изменения конфигов выполните:

```bash
sudo rkn-watcher apply
```
