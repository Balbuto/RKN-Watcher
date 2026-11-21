# Переход на v3.2.1

## Кратко

| Что | Действие |
|---|---|
| обновление через `installer.sh` | ничего делать не нужно, `lib/` копируется автоматически |
| обновление вручную (копированием файлов) | **скопировать каталог `lib/`** в `/opt/rkn-watcher/` |
| IPv6-записи в JSON | теперь работают, удалять их больше не нужно |
| новые ключи | `NETFILTER_BACKEND`, `SNAPSHOT_KEEP`, `SNAPSHOT_MAX_AGE_DAYS` — можно не добавлять, есть дефолты |
| старые конфиги | совместимы без изменений |

## Что изменилось в v3.2.1

- **модульная структура**: точка входа `rkn-watcher.sh` — 16 строк, логика в
  `lib/common.sh`, `lib/firewall.sh`, `lib/snapshots.sh`, `lib/lists.sh`,
  `lib/services.sh`, `lib/ui.sh`, `lib/cli.sh`, константы в `lib/config.sh`.
  Старый одиночный скрипт без `lib/` не запустится: он завершится с сообщением
  `Не найден каталог модулей lib/`;
- **IPv6 для allow/deny-списков**: адреса разводятся по `*6`-наборам и `ip6tables`
  (цепочка `RKN_GEOIP_HOOK6`). Ранее отклонявшиеся IPv6-записи теперь применяются —
  если вы удаляли их «на всякий случай», их можно вернуть;
- **`NETFILTER_BACKEND`** (`auto`/`legacy`/`nft`): явный выбор бэкенда, проверка
  фактического состояния в `doctor`;
- **ротация снапшотов**: `SNAPSHOT_MAX_AGE_DAYS` (30 дней) и `SNAPSHOT_KEEP` (10),
  новая команда `rkn-watcher snapshots`;
- `get_setting` при дублировании ключа берёт последнее значение (как shell), а
  `doctor` предупреждает о дублях.

## Рекомендуемый порядок обновления

```bash
cd RKN-Watcher
git pull
sha256sum -c SHA256SUMS
sudo ./installer.sh install          # конфигурацию сохранить
sudo rkn-watcher apply --dry-run     # посмотреть новый набор правил
sudo rkn-watcher doctor              # окружение, бэкенд, соответствие правил
sudo rkn-watcher apply
sudo rkn-watcher status
```

## Обновление вручную (без installer.sh)

```bash
sudo install -d -m 0755 /opt/rkn-watcher/lib
sudo install -m 0755 rkn-watcher.sh /opt/rkn-watcher/
sudo install -m 0755 lib/*.sh /opt/rkn-watcher/lib/
sudo install -m 0755 config_tool.py geoip_apply.py /opt/rkn-watcher/
sudo rkn-watcher apply
```

## Что проверить после миграции

```bash
sudo rkn-watcher status
sudo rkn-watcher doctor
sudo iptables -L INPUT -v -n
sudo ipset list TSPUIPS | head -3
sudo ipset list GOVIPS | head -3
sudo ipset list GEOIP_COUNTRIES_ALLOW | head -3
# IPv6 (если установлен ip6tables)
sudo ip6tables -L RKN_GEOIP_HOOK6 -v -n
sudo ipset list GEOIP_ALLOW_IPS6 | head -3
```

## Переход на v3.2

### Что изменилось в v3.2

Аудит v3.1 показал четыре ошибки, которые исправлены в v3.2:

1. **fail-open в bash** — `ENABLE_TSPUBLOCK="true"`/`"1"`/`"on"` выключали блокировку
   молча. Теперь значения нормализуются, а некорректные приводят к ошибке `apply`.
2. **риск самоблока** — в GeoIP-хук добавлены `lo` и `ESTABLISHED,RELATED`.
3. **deny/allow-порты не работали при `FILTER_PORTS ≠ all`** — выделена стадия
   `RKN_DENY`.
4. **`install` из `/usr/local/bin/rkn-watcher` падал** — путь к helper-скриптам
   разрешается через `readlink -f` и ищется также в `/opt/rkn-watcher`.

Новые цепочки: `RKN_DENY`, `RKN_PROTECT`; новые наборы: `TSPUIPS6`, `GOVIPS6`
(если установлен `ip6tables`). Старые цепочки и наборы сохраняют имена.

### Новый ключ PORT_POLICY

По умолчанию `PORT_POLICY=geoip_only` — поведение, совместимое с v3.1 (GeoIP
фильтрует порты из `FILTER_PORTS`, остальные открыты). Если нужен режим
«открыты только порты из FILTER_PORTS»:

```bash
echo 'PORT_POLICY="strict"' | sudo tee -a /etc/rkn-watcher/settings.conf
sudo rkn-watcher apply
```

### Если список резко изменился

Sanity-гейт не применит список, который уменьшился больше чем вдвое или вырос больше
чем в 5 раз. Осознанный обход: `sudo RKN_ALLOW_LIST_SHRINK=1 rkn-watcher update`.

## Переход с версий до v3

В старых версиях проекта были следующие проблемы:

- `ipset` очищался до успешной загрузки нового списка;
- при повторном применении накапливались дубли `iptables`-правил;
- конфликтовали `cron` и фоновый демон;
- пользовательский ввод обрабатывался частично небезопасно;
- при uninstall удалялись глобальные firewall-файлы;
- GeoIP по странам был заявлен, но не применялся как реальный country-фильтр.

В v3 появилась текущая схема атомарного обновления, systemd и CIDR-фильтрации.
Начиная с v3.2.1 IPv6-записи принимаются, а не отклоняются.

## Рекомендуемый способ перехода с v1/v2

### Вариант 1. Обновление существующей установки

```bash
cd RKN-Watcher
git pull
sudo ./installer.sh install
```

При запросе выберите сохранение текущей конфигурации, затем выполните:

```bash
sudo rkn-watcher apply
sudo rkn-watcher status
```

### Вариант 2. Чистая установка

1. удалить старую версию (`sudo ./installer.sh uninstall`);
2. установить текущую версию через `sudo ./installer.sh`;
3. перенести allow/deny-записи (IPv4 и IPv6) и коды стран;
4. проверить список стран до включения GeoIP.

## Проверка файлов релиза

```bash
sha256sum -c SHA256SUMS
```
