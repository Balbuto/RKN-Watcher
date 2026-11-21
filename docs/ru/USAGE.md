# Использование

## Основные команды

```bash
sudo rkn-watcher install                 # установка / обновление кода
sudo rkn-watcher update                  # обновить TSPUBLOCK и GOVIPS и применить
sudo rkn-watcher apply                   # пере-применить правила из текущей конфигурации
sudo rkn-watcher apply --dry-run         # показать правила без применения
sudo rkn-watcher status                  # состояние (--json для мониторинга)
sudo rkn-watcher doctor                  # диагностика окружения и правил
sudo rkn-watcher metrics                 # метрики в формате Prometheus
sudo rkn-watcher snapshot                # снапшот правил вручную
sudo rkn-watcher snapshots               # список снапшотов
sudo rkn-watcher rollback [STAMP]        # откат к снапшоту
sudo rkn-watcher uninstall               # удалить приложение
sudo rkn-watcher --help | --version
```

Через установщик:

```bash
sudo ./installer.sh
sudo ./installer.sh install
sudo ./installer.sh uninstall
sudo ./installer.sh deps
sudo ./installer.sh status
sudo ./installer.sh nft      # проверка nftables: пакет, nft, ruleset, бэкенд iptables
```

`status`, `metrics` и `doctor` работают и без `root` (часть проверок в этом случае
недоступна и помечается в выводе).

### Флаги

| Флаг | Где | Смысл |
|---|---|---|
| `--quiet` | `update` | минимум вывода, для systemd |
| `--dry-run` | `apply` | распечатать payload `iptables-restore` без применения |
| `--force` | `apply` | пересобрать наборы, игнорируя сигнатуры содержимого |
| `--json` | `status` | машинный вывод |
| `--yes` | `install` | неинтерактивный режим, сохраняет текущую конфигурацию |

## Защита от самоблока

```bash
sudo rkn-watcher allow-my-ip              # IP из $SSH_CONNECTION → allow-список + apply
sudo rkn-watcher allow-my-ip 203.0.113.7  # вручную (IPv4 или IPv6)
sudo rkn-watcher block-ip 198.51.100.0/24
sudo rkn-watcher unblock-ip 198.51.100.0/24
```

`block-ip`/`unblock-ip` добавляют запись в `blacklist.json` и сразу пере-применяют
правила — перезагружать ничего не нужно.

Перед включением GeoIP в меню скрипт проверяет, есть ли ваш SSH-IP в allow-списке,
и предлагает добавить его.

## Netfilter-бэкенд

```bash
sudo rkn-watcher doctor | grep -i backend
```

Доктор печатает заданное значение `NETFILTER_BACKEND` и фактический бэкенд, через
который работает `iptables`, а также предупреждает о расхождении (частая причина
«правила применились, но трафик не фильтруется» — правила ушли в `iptables-nft`,
а смотрите вы `iptables-legacy`).

Смена бэкенда:

```bash
sudo rkn-watcher          # Настройки → 10) Netfilter-бэкенд (auto/legacy/nft)
```

или напрямую:

```bash
echo 'NETFILTER_BACKEND="legacy"' | sudo tee -a /etc/rkn-watcher/settings.conf
sudo rkn-watcher apply
```

## Снапшоты и откат

Перед каждым `apply`/`update` сохраняются `iptables-save`, `ip6tables-save` и
`ipset save` в `/var/lib/rkn-watcher/snapshots/<timestamp>/`.

```bash
sudo rkn-watcher snapshot            # создать снапшот вручную
sudo rkn-watcher snapshots           # список со временем и размером
sudo rkn-watcher rollback            # откатить к последнему (перед последним apply)
sudo rkn-watcher rollback 20260809-030000
```

Хранение: последние `SNAPSHOT_KEEP` (по умолчанию 10) не удаляются никогда,
всё старше `SNAPSHOT_MAX_AGE_DAYS` (по умолчанию 30 дней) удаляется автоматически.

При потере доступа по SSH откат из консоли/IPMI — одна команда, это дешевле, чем
восстанавливать правила вручную.

## Неинтерактивный режим

```bash
sudo rkn-watcher install --yes     # обновить код, не меняя текущую конфигурацию
```

## Интерактивное меню

```bash
sudo rkn-watcher
```

Главное меню:

1. Блок-листы — включение/отключение `TSPUBLOCK` и `GOVIPS`, обновление списков,
   показ `iptables` / `ipset`;
2. GeoIP — enable/disable, страны, allow/deny IP (IPv4 и IPv6) и порты;
3. Настройки — `FILTER_PORTS`, `LOG_RST`, `AUTO_UPDATE`, политика по портам,
   снапшоты, диагностика, netfilter-бэкенд;
4. Статус;
5. Логи;
6. Переустановить / обновить;
7. Удалить;
8. Диагностика.

Подменю «Настройки»:

```text
1) Изменить FILTER_PORTS
2) Вкл/выкл LOG_RST
3) Вкл/выкл AUTO_UPDATE
4) Пере-применить правила
5) Политика по портам (geoip_only / strict)
6) Снапшот правил
7) Откатить последний снапшот
8) Диагностика (doctor)
9) Список снапшотов
10) Netfilter-бэкенд (auto/legacy/nft)
0) Назад
```

### Ввод GeoIP-адресов

Allow/deny IP принимают IPv4 **и** IPv6-адреса и CIDR: `1.2.3.4`, `10.0.0.0/24`,
`2001:db8::1`, `2001:db8::/32`. Семейство определяется автоматически. Для
сериализованных изменений используйте меню или `config_tool.py`, после ручной правки
выполните `sudo rkn-watcher apply`.

## Обновление списков

```bash
sudo rkn-watcher update
```

Плановый запуск — `rkn-watcher-update.timer`, ежедневно в `03:00` с
`RandomizedDelaySec=1h` (рассеивание нагрузки на источники и на xtables lock).

Защита от плохих данных:

- условный GET (`curl -z`): неизменившийся источник не перекачивается;
- сигнатуры наборов: при неизменном содержимом `ipset` не пересобирается;
- sanity-гейт: резкое уменьшение/рост списка не применяется;
- сбой `ipset restore`/`swap` возвращает ошибку, а не «успех», старый набор сохраняется.

## Метрики

```bash
sudo rkn-watcher metrics > /var/lib/node_exporter/textfile/rkn-watcher.prom
sudo rkn-watcher status --json | jq
```

## Логи

```bash
sudo tail -n 100 /var/log/rkn-watcher/update.log
sudo tail -n 100 /var/log/rkn-watcher/actions.log
sudo tail -n 100 /var/log/rkn-watcher/geoip.log
```

Ротация настроена в `/etc/logrotate.d/rkn-watcher`.

## Проверка таймера

```bash
systemctl status rkn-watcher-update.timer
systemctl list-timers | grep rkn-watcher
```

## Проверка правил и наборов

```bash
# IPv4
sudo iptables -L INPUT -v -n
sudo iptables -L TSPUBLOCK -v -n
sudo iptables -L GOVBLOCK -v -n
sudo iptables -L RKN_GEOIP_HOOK -v -n
sudo iptables -L RKN_DENY -v -n
sudo iptables -L GEOIP_DROP -v -n
sudo iptables -L RKN_PROTECT -v -n

sudo ipset list TSPUIPS | head -20
sudo ipset list GOVIPS | head -20
sudo ipset list GEOIP_ALLOW_IPS | head -20
sudo ipset list GEOIP_DENY_IPS | head -20
sudo ipset list GEOIP_COUNTRIES_ALLOW | head -20

# IPv6 (если установлен ip6tables)
sudo ip6tables -L INPUT -v -n
sudo ip6tables -L RKN_GEOIP_HOOK6 -v -n
sudo ip6tables -L TSPUBLOCK6 -v -n
sudo ipset list TSPUIPS6 | head -20
sudo ipset list GEOIP_ALLOW_IPS6 | head -20
sudo ipset list GEOIP_DENY_IPS6 | head -20
sudo ipset list GEOIP_COUNTRIES_ALLOW6 | head -20
```

Если бэкенд не `auto`, используйте соответствующие утилиты (`iptables-legacy`,
`iptables-nft`) — иначе увидите пустые цепочки.
