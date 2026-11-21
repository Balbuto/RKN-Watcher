# Тесты v3.2.1

В этой папке лежит небольшой набор безопасных mock-тестов для проверки логики `iptables` / `ipset` без изменения реального firewall сервера.

## Что проверяется

### Метаданные релиза
- версия в `VERSION`, `rkn-watcher.sh`, README, примечаниях к релизу и changelog остаётся согласованной.

### Для `rkn-watcher.sh`
- корректное добавление `TSPUBLOCK` и `GOVIPS`;
- отсутствие дублирования hook-правил в `INPUT`;
- успешное наполнение `ipset` при update;
- корректная ошибка при неудачной загрузке списков;
- сохранение старого рабочего `ipset` при сбое update;
- очистка управляемых цепочек и `ipset` через `remove_managed_firewall()`.

### Для `geoip_apply.py`
- создание `GEOIP_ALLOW_IPS`, `GEOIP_DENY_IPS`, `GEOIP_COUNTRIES_ALLOW`;
- корректное построение цепочек `RKN_GEOIP_HOOK` и `GEOIP_DROP`;
- отсутствие дублирования hook в `INPUT` при повторном apply;
- очистка hook и цепочек при `enabled=false`;
- обработка legacy-значения `"false"` как выключенного GeoIP.

## Запуск

Из корня репозитория:

```bash
chmod +x tests/run_tests.sh
./tests/run_tests.sh
```

## Требования

- `bash`
- `python3`
- запуск от обычного пользователя допустим
- root не нужен

## Примечание

Это не integration-тесты реального kernel firewall, а тесты логики скриптов через mock-реализации `iptables`, `ipset`, `curl` и связанных команд.

## Что покрывают тесты в v3.2

Помимо «счастливых путей» добавлены регрессии на найденные при аудите ошибки:

| Регрессия | Проверяемый сценарий |
|---|---|
| fail-open boolean | `ENABLE_TSPUBLOCK="true"`/`"1"` не выключает блокировку |
| fail-closed | некорректное boolean-значение — ошибка, а не тихое отключение |
| маскировка сбоя `ipset` | `ipset restore` падает → `update` возвращает 1 |
| sanity-гейт | резкое уменьшение списка не применяется, `RKN_ALLOW_LIST_SHRINK=1` обходит |
| независимость deny | deny IP/порты работают при любом `FILTER_PORTS` |
| защита от самоблока | в хуке присутствуют `-i lo` и `ESTABLISHED,RELATED` |
| `PORT_POLICY=strict` | открыты только порты из `FILTER_PORTS` |
| `--dry-run` | состояние firewall не меняется |
| понятные ошибки | `FILTER_PORTS="443;80"` → сообщение, а не трейсбек |

Стенд не требует root: `iptables`, `ip6tables`, `iptables-restore`, `iptables-save`,
`ipset`, `ipset save` и `curl` подменяются mock-реализациями на Python.

## Что покрывают тесты в v3.2.1

| Регрессия | Сценарий |
|---|---|
| модульная сборка | библиотека собирается из `lib/*.sh`; проверяется, что все функции на месте |
| IPv6 allow/deny | `2001:db8::/32` попадает в `GEOIP_ALLOW_IPS6`, `2001:db8:dead::/48` — в `GEOIP_DENY_IPS6`, оба видны в `ip6tables` |
| некорректный адрес | `2001:db8:::1` в allow-списке → ошибка конфигурации, а не тихий пропуск |
| IPv6 в `config_tool.py` | `add-ip 2001:db8::1` принимается, `add-ip 2001:db8:::1` отклоняется |
| netfilter-бэкенд | `NETFILTER_BACKEND=legacy` вызывает `iptables-legacy`; `bogus` — ошибка конфигурации |
| ротация снапшотов | каталог старше `SNAPSHOT_MAX_AGE_DAYS` удаляется, свежий и последние `SNAPSHOT_KEEP` сохраняются |
| nftables в установщике | пакет/утилита/пустой ruleset/бэкенд `iptables` проверяются; без `nftables` — ненулевой код возврата |

## Моки

| Мок | Особенности |
|---|---|
| `iptables` | состояние в `$STATE/iptables.json`, понимает `-w N`, `-N/-F/-X/-A/-I/-C/-D/-L` |
| `ip6tables` | **отдельное** состояние `$STATE/iptables6.json`, иначе v4- и v6-правила смешиваются |
| `iptables-restore` / `iptables-save` | `iptables6.json` при вызове как `ip6tables-*`, поддержка `--noflush` |
| `ipset` | `create/add/destroy/swap/flush`, наборы в `$STATE/ipset.json` |
| `curl` | управляемые ответы и коды ошибок для источников списков |

Запускать с таймаутом (`timeout 150 bash tests/run_tests.sh`): при зависании мока
прогон не должен висеть.

## Итог v3.2.1

```text
27 проверок, All tests passed.
```
