# Интерактивный установщик

Файл:

```text
installer.sh
```

Это рекомендуемая точка входа для установки и удаления RKN Watcher.

## Что делает установщик

### При установке

- проверяет, что он запущен от `root`;
- проверяет совместимость с `apt` / `dpkg`;
- проверяет обязательные зависимости;
- устанавливает отсутствующие пакеты;
- сохраняет список пакетов, доустановленных именно этим установщиком;
- **проверяет nftables** (см. ниже) и останавливает установку, если проверка не пройдена;
- запускает `rkn-watcher.sh install` (который копирует и модули `lib/`).

## Проверка nftables

Современные Debian/Ubuntu управляют netfilter через `nftables`; `iptables` в них —
надстройка (либо над `nft`, либо над `legacy`). Установщик проверяет четыре вещи:

| Проверка | Что значит | Реакция |
|---|---|---|
| пакет `nftables` установлен | `dpkg-query` знает пакет | ставится автоматически (`apt-get install -y nftables`) и запоминается в манифесте |
| утилита `nft` доступна в `PATH` | правила можно прочитать/проверить | ошибка, установка останавливается |
| `nft list ruleset` выполняется | ядро с `nf_tables` и есть `CAP_NET_ADMIN` | ошибка с подсказкой (`modprobe nf_tables`, контейнер без прав) |
| ruleset не пуст | правила реально загружены | предупреждение + предложение загрузить `nftables.service` (если в `/etc/nftables.conf` правила есть) |

Дополнительно установщик показывает, через какой бэкенд работает `iptables`:

```text
[OK] iptables работает через nft-бэкенд (xtables-nft-multi)
[WARN] iptables работает через legacy-бэкенд (xtables-legacy-multi) — правила не попадут в nftables
       Если нужен nft: NETFILTER_BACKEND="nft" в /etc/rkn-watcher/settings.conf (или пункт 10 меню настроек)
```

Пустой ruleset при выключенном `nftables.service` — самая частая причина ситуации
«правила применены, но после перезагрузки исчезли». В интерактивном режиме установщик
предложит включить сервис; при `install --yes` вопросов не задаёт, только
предупреждает.

Проверить отдельно, без установки:

```bash
sudo ./installer.sh nft      # пакет + утилита + ruleset + бэкенд iptables
sudo ./installer.sh deps     # блок «Netfilter» со сводкой
```

или пункт меню «5) Проверить nftables».

### При удалении

- запускает полное удаление всех изменений, внесённых RKN Watcher;
- при необходимости выполняет аварийную очистку, даже если основной скрипт уже
  повреждён или отсутствует;
- может дополнительно удалить пакеты, которые ранее установил сам установщик.

## Запуск

```bash
sudo ./installer.sh
```

## Пункты меню

1. Установить / обновить RKN Watcher
2. Проверить зависимости
3. Полное удаление всех внесённых изменений
4. Показать статус
5. Проверить nftables
0. Выход

## Прямые команды

```bash
sudo ./installer.sh install
sudo ./installer.sh uninstall
sudo ./installer.sh deps
sudo ./installer.sh status
sudo ./installer.sh nft
```

## Какие зависимости проверяются

- `iptables`
- `ipset`
- `nftables`
- `curl`
- `ca-certificates`
- `python3`
- `util-linux` (`flock`)

`ip6tables` входит в пакет `iptables` на Debian/Ubuntu, поэтому отдельно не
устанавливается — при его наличии IPv6-фильтрация включается автоматически.

## Что удаляется при uninstall

- `systemd`-юниты `rkn-watcher-update.timer`, `rkn-watcher-update.service`,
  `rkn-watcher-boot.service`;
- управляемые цепочки `iptables` **и** `ip6tables`
  (`TSPUBLOCK`, `GOVBLOCK`, `RKN_GEOIP_HOOK`, `RKN_DENY`, `GEOIP_DROP`, `RKN_PROTECT`
  и их `*6`-аналоги);
- управляемые `ipset`-наборы IPv4 и IPv6 (`TSPUIPS`, `GOVIPS`, `GEOIP_ALLOW_IPS`,
  `GEOIP_DENY_IPS`, `GEOIP_COUNTRIES_ALLOW` и `*6`-варианты);
- `/opt/rkn-watcher` (включая `lib/`)
- `/etc/rkn-watcher`
- `/var/lib/rkn-watcher` (включая `snapshots/` и `backups/`)
- `/var/log/rkn-watcher`
- `/usr/local/bin/rkn-watcher`

После этого установщик может предложить удалить пакеты, которые он сам доустановил.
