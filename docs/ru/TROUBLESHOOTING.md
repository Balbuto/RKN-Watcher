# Решение проблем

## Сначала — диагностика

```bash
sudo rkn-watcher doctor
```

Проверяет:

- зависимости (`iptables`, `ipset`, `curl`, `python3`, `flock`) и наличие `ip6tables`;
- модули ядра `ip_set`, `xt_set`, `xt_conntrack`, `xt_multiport`;
- **netfilter-бэкенд**: заданный `NETFILTER_BACKEND` и фактический (через какой
  реально работает `iptables`), с предупреждением о расхождении;
- конфликты с `ufw` / `firewalld` / `docker`;
- корректность boolean-ключей `settings.conf` и дублирующиеся ключи;
- соответствие реальных правил конфигурации (есть ли хук при `ENABLE_*=y` и наоборот);
- доступность источников списков и состояние таймера.

Дальше — только если `doctor` не помог.

## «Не найден каталог модулей lib/»

Начиная с v3.2.1 скрипт состоит из точки входа и модулей. Если вы обновляли
установку копированием файлов, каталог `lib/` не попал в `/opt/rkn-watcher`.

```bash
sudo install -d -m 0755 /opt/rkn-watcher/lib
sudo install -m 0755 lib/*.sh /opt/rkn-watcher/lib/
sudo rkn-watcher apply
```

Либо переустановите через `sudo ./installer.sh install` — он копирует модули сам.

## Потерял доступ по SSH после включения GeoIP

Правила не рвут установленные сессии, но новая сессия с «неразрешённого» адреса
не установится. Из консоли/IPMI:

```bash
sudo rkn-watcher rollback        # откат к снапшоту перед последним apply
sudo rkn-watcher allow-my-ip     # разрешить текущий IP
sudo rkn-watcher status
```

## Правила применяются, но трафик не фильтруется

Почти всегда это **расхождение netfilter-бэкендов**: правила записаны через
`iptables-nft`, а смотрите/фильтруете вы через `iptables-legacy` (или наоборот).

```bash
sudo rkn-watcher doctor | grep -i backend
# netfilter backend: auto (фактически: legacy, утилита: iptables-legacy)
```

Если в системе оба бэкенда, задайте нужный явно:

```bash
echo 'NETFILTER_BACKEND="nft"' | sudo tee -a /etc/rkn-watcher/settings.conf
sudo rkn-watcher apply
```

Проверьте, что видите свои цепочки той же утилитой:

```bash
sudo iptables-nft -L RKN_GEOIP_HOOK -v -n     # или iptables-legacy
```

## IPv6-правила не создаются

```bash
command -v ip6tables && sudo ip6tables -L INPUT -v -n
```

Причины:

- `ip6tables` не установлен (обычно приходит с пакетом `iptables`) — IPv6-часть
  пропускается с предупреждением, `doctor` пишет `ip6tables: нет (IPv6 не защищён)`;
- в списках нет IPv6-записей и `PORT_POLICY=geoip_only` — тогда IPv6-хук не нужен
  и не создаётся (это нормально, не ошибка).

## IPv6-адрес в списке отклонён

Раньше это было ожидаемым (v3.1 поддерживал только IPv4), с v3.2.1 — нет: IPv6
принимается. Если ошибка осталась, проверьте запись:

```bash
python3 -c 'import ipaddress,sys; ipaddress.ip_network(sys.argv[1], strict=False)' 2001:db8::/32
```

`2001:db8:::1`, `2001:db8::/129` и подобные записи — ошибка конфигурации, а не
молчаливый пропуск.

## «Update completed with errors»

Подробности в `update.log`. Типовые причины:

- источник недоступен — старый набор продолжает работать, повторите позже;
- `sanity check failed` — список изменился в 2+ раза; проверьте источник,
  при ожидаемом изменении `sudo RKN_ALLOW_LIST_SHRINK=1 rkn-watcher update`;
- `ipset restore failed` — проверьте свободное место и `maxelem`, старый набор сохранён.

## Правила не применились: «Некорректное boolean-значение»

Проверьте `settings.conf`: допустимы только `y/n`, `yes/no`, `true/false`, `1/0`,
`on/off`. Любое другое значение блокирует применение (fail-closed) — раньше это молча
отключало блокировку.

Если ключ встречается в файле несколько раз, действует последнее значение — `doctor`
показывает такие ключи отдельной строкой:

```bash
sudo rkn-watcher doctor | grep -i дублир
```

## Установщик: «nft не может прочитать ruleset» или «ruleset пуст»

Установщик проверяет nftables перед установкой. Сообщения и что делать:

```bash
sudo nft list ruleset            # читается? значит права/ядро в порядке
modprobe nf_tables               # если модуль не загружен
uname -r                         # очень старое ядро без nf_tables — обновите ядро
```

- **«Утилита nft не найдена»** — `apt-get install -y nftables` (установщик делает это сам
  в интерактивном режиме);
- **«nft не может прочитать ruleset»** — чаще всего контейнер без `CAP_NET_ADMIN`
  (нужен `--privileged` или проброс `CAP_NET_ADMIN`) либо ядро без `nf_tables`;
- **«ruleset пуст»** — правил нет; если в `/etc/nftables.conf` они есть, значит
  `nftables.service` не загружен:

  ```bash
  sudo systemctl enable --now nftables.service
  sudo nft list ruleset
  ```

Отдельная проверка без установки: `sudo ./installer.sh nft` (или меню, пункт 5).

## После перезагрузки правила nftables пропали

Правила, загруженные «руками», не сохраняются. Включите сервис:

```bash
sudo systemctl enable nftables.service
systemctl is-enabled nftables.service
```

Собственные правила RKN Watcher восстанавливаются отдельным юнитом
`rkn-watcher-boot.service` (iptables/ipset), он от nftables не зависит.

## Установщик сообщает, что он запущен не от root

```bash
sudo ./installer.sh
```

## Не найдены helper-файлы

Причина: `rkn-watcher.sh` запущен отдельно, без `config_tool.py`, `geoip_apply.py`
и каталога `lib/`.

Решение: использовать `git clone`, либо положить `installer.sh`, `rkn-watcher.sh`,
`lib/`, `config_tool.py`, `geoip_apply.py` в одну директорию.

## Не загружаются списки TSPUBLOCK / GOVIPS

```bash
curl -I https://github.com/
curl -I https://raw.githubusercontent.com/
sudo tail -n 100 /var/log/rkn-watcher/update.log
```

При ошибке загрузки старый рабочий `ipset` сохраняется.

## Country GeoIP не применяет список стран

```bash
sudo cat /etc/rkn-watcher/whitelist.json
sudo ipset list GEOIP_COUNTRIES_ALLOW | head -20
sudo ipset list GEOIP_COUNTRIES_ALLOW6 | head -20
```

Если набор пуст:

- проверьте доступ к `ipdeny.com`;
- проверьте код страны (`FI`, `DE`, `JP` — ISO alpha-2, верхний регистр);
- посмотрите `/var/log/rkn-watcher/geoip.log` — там причина (`countries=…`).

## После изменения конфига правила не обновились

```bash
sudo rkn-watcher apply
```

## Таймер не запускается

```bash
systemctl status rkn-watcher-update.timer
systemctl status rkn-watcher-update.service
systemctl list-timers | grep rkn-watcher
```

Если таймер выключен:

```bash
sudo systemctl enable --now rkn-watcher-update.timer
```

## Включён GeoIP и доступ пропал слишком широко

Вероятная причина: `enabled=true`, заполнены `countries`, ваш IP или страна не попали
в allow-набор.

Решение:

- временно добавить свой IP в allow (`rkn-watcher allow-my-ip`);
- либо отключить GeoIP;
- затем скорректировать список стран.

## Снапшоты занимают много места

```bash
sudo rkn-watcher snapshots
```

Хранение ограничено: последние `SNAPSHOT_KEEP` (10) + всё, что младше
`SNAPSHOT_MAX_AGE_DAYS` (30 дней). Уменьшить:

```ini
SNAPSHOT_KEEP="5"
SNAPSHOT_MAX_AGE_DAYS="14"
```

Ротация выполняется при создании следующего снапшота (`apply`/`update`/`snapshot`).

## Как быстро отключить только GeoIP

```bash
sudo /opt/rkn-watcher/config_tool.py set-enabled false
sudo rkn-watcher apply
```
