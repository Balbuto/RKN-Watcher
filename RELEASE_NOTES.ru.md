# Примечания к релизу — RKN Watcher v3.2.1

## Основное

`v3.2.1` закрывает все рекомендации внешнего аудита v3.1, кроме проверки подписи
сторонних источников (на неё влиять нельзя — чужие репозитории). Поведение по
умолчанию и формат конфигурации не меняются.

## Что нового

### Модульная структура

Монолит на 2050 строк разбит на модули; точка входа `rkn-watcher.sh` — 16 строк:

```text
lib/config.sh     пути, константы, загрузка модулей
lib/common.sh     вывод, логи, settings.conf, валидация, установка helper-файлов и lib/
lib/firewall.sh   ipset, правила RST, выбор netfilter-бэкенда
lib/snapshots.sh  снапшоты, ротация, откат
lib/lists.sh      загрузка списков, санитизация, sanity-гейт
lib/services.sh   systemd, logrotate, install/uninstall
lib/ui.sh         статус, metrics, doctor, меню
lib/cli.sh        разбор аргументов и main()
```

Модули устанавливаются в `/opt/rkn-watcher/lib` автоматически.

### IPv6 для allow/deny-списков

`whitelist.ips` и `blacklist.ips` принимают IPv4 **и** IPv6. Адреса разделяются по
семействам: IPv6 уходит в наборы `GEOIP_ALLOW_IPS6`, `GEOIP_DENY_IPS6`,
`GEOIP_COUNTRIES_ALLOW6` (`family inet6`) и применяется в `ip6tables` через цепочку
`RKN_GEOIP_HOOK6`. Раньше IPv6-запись отклонялась, и на dual-stack сервере
allow-список не защищал от IPv6-трафика.

### Выбор netfilter-бэкенда

Новый ключ `NETFILTER_BACKEND=auto|legacy|nft`. `doctor` показывает заданный и
фактический бэкенд и предупреждает о расхождении — это самая частая причина
«правила применились, но не работают».

### Проверка nftables при установке

Установщик больше не полагается на «наверное, nftables есть». Перед установкой он
проверяет пакет `nftables`, утилиту `nft`, читаемость ruleset и сообщает, через какой
бэкенд работает `iptables` (`nft` или `legacy`). Пустой ruleset при неактивном
`nftables.service` — частая причина «правила исчезли после перезагрузки», теперь это
видно сразу. Отдельная проверка: `sudo ./installer.sh nft`.

### Снапшоты

Ротация по возрасту: `SNAPSHOT_MAX_AGE_DAYS` (по умолчанию 30) и `SNAPSHOT_KEEP`
(по умолчанию 10 — столько последних не удаляется никогда). Новая команда
`sudo rkn-watcher snapshots` и пункт меню со списком и размерами.

### Прочее

- при дублировании ключа в `settings.conf` действует последнее значение (как в shell),
  `doctor` выводит список дублей;
- `config_tool.py` принимает IPv6; некорректный адрес — явная ошибка;
- пункты меню «Настройки» упорядочены (8 — диагностика, 9 — снапшоты, 10 — бэкенд).

## Эксплуатация

```bash
sudo rkn-watcher snapshots                 # список снапшотов
sudo rkn-watcher doctor | grep -i backend  # какой бэкенд реально используется
sudo ip6tables -L RKN_GEOIP_HOOK6 -v -n    # IPv6-правила
sudo rkn-watcher apply --dry-run           # что будет применено
```

## Совместимость

- `settings.conf` и JSON-конфиги v3.1/v3.2 читаются без изменений; новые ключи имеют
  дефолты;
- имена наборов и цепочек сохранены, добавлены только `*6`-варианты;
- при обновлении **вручную копированием файлов** не забудьте про каталог `lib/`
  (через `installer.sh` он копируется сам).

## Проверено

- 24 mock-теста, включая новые регрессии: IPv6 в allow/deny и `ip6tables`, отказ на
  некорректный адрес, выбор и валидация бэкенда, ротация снапшотов;
- `bash -n`, `shellcheck -S warning` (0 предупреждений), `pyflakes`, `py_compile`;
- `./release.sh --check` — манифест из 47 файлов сходится;
- прогон на стенде без root: `install` → `update` → `apply` (`auto` и `legacy`) →
  `snapshots` → `doctor`.

## Обновление

```bash
cd RKN-Watcher
git pull
sha256sum -c SHA256SUMS
sudo ./installer.sh install
sudo rkn-watcher apply --dry-run
sudo rkn-watcher doctor
sudo rkn-watcher apply
```
