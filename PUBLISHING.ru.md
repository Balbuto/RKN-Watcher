# Публикация релиза

## 1. Проверка перед публикацией

Из корня релизной папки:

```bash
bash -n installer.sh rkn-watcher.sh lib/*.sh tests/run_tests.sh release.sh
shellcheck -S warning --shell=bash installer.sh rkn-watcher.sh lib/*.sh release.sh tests/run_tests.sh
python3 -m py_compile config_tool.py geoip_apply.py
python3 -m pyflakes config_tool.py geoip_apply.py
timeout 150 bash tests/run_tests.sh
./release.sh --check
```

Ожидаемый результат:

- bash-синтаксис без ошибок (включая все 8 модулей `lib/`);
- `shellcheck -S warning` — без замечаний;
- `py_compile` / `pyflakes` — чисто;
- `All tests passed.` (27 проверок);
- каждая запись в `SHA256SUMS` имеет статус `OK`.

Всё это же выполняет `./release.sh` (проверка версий, пересборка манифеста, архив).

## 2. Версия и тег

Версия хранится в двух местах и должна совпадать:

- `VERSION`;
- `VERSION="..."` в `lib/config.sh`.

`release.sh` проверяет это сам и не соберёт релиз при расхождении. Тег:

```bash
git tag -a v3.2.1 -m "RKN Watcher v3.2.1"
git push origin v3.2.1
```

## 3. Что приложить в GitHub Release

Описание релиза — `RELEASE_NOTES.ru.md` или `RELEASE_NOTES.en.md`.
Артефакты собирает `./release.sh`:

| Файл | Что это |
|---|---|
| `rkn-watcher-3.2.1.tar.gz` | полный исходник релиза (включая `.github/workflows`, `docs/`, `tests/`) |
| `rkn-watcher-3.2.1.zip` | то же в zip, для Windows/веб-загрузки |
| `SHA256SUMS` | контрольные суммы всех 47 файлов релиза (проверяются внутри архива) |
| `rkn-watcher-3.2.1.tar.gz.sha256`, `rkn-watcher-3.2.1.zip.sha256` | суммы самих архивов |

Оба архива содержат `SHA256SUMS`, поэтому проверка работает сразу после распаковки:

```bash
tar xzf rkn-watcher-3.2.1.tar.gz -C rkn-watcher-3.2.1 --one-top-level
cd rkn-watcher-3.2.1 && sha256sum -c SHA256SUMS
```

В архивах нормализованы права (`*.sh` — `0755`, остальное — `0644`) и владелец
(`0/0`), поэтому распаковка от любого пользователя даёт рабочий набор файлов.

## 4. Что не нужно коммитить

Не включайте runtime-данные с сервера:

- `/etc/rkn-watcher/*`
- `/var/log/rkn-watcher/*`
- `/var/lib/rkn-watcher/*` (включая `snapshots/`, `backups/`, `state/`)
- systemd unit-файлы с уже установленной машины
- реальные дампы `iptables` / `ip6tables` / `ipset`

## 5. Автоматизация релиза

```bash
./release.sh            # проверить версии, пересобрать SHA256SUMS, собрать архив
./release.sh --check    # только проверить существующий SHA256SUMS (используется в CI)
./release.sh --sign     # дополнительно подписать манифест и архив GPG-ключом
```

Манифест покрывает 47 файлов: точку входа, все модули `lib/*.sh`, python-хелперы,
`VERSION`, `LICENSE`, README/CHANGELOG/RELEASE_NOTES/PUBLISHING (ru/en/md),
`docs/**`, `tests/**` и workflow CI. Новый файл в релизе = новая строка
в `RELEASE_FILES` внутри `release.sh`.

CI (`.github/workflows/tests.yml`) выполняет `bash -n`, `shellcheck -S warning`,
`py_compile`, `pyflakes`, mock-тесты и `./release.sh --check` — релиз нельзя
опубликовать с рассинхронизированным манифестом или версией.

## 6. Что проверять в документации при релизе

- версия в `README*.md`, `CHANGELOG*`, `RELEASE_NOTES*`, `docs/README.md`;
- новые ключи `settings.conf` описаны в `docs/{ru,en}/CONFIGURATION.md`;
- новые команды — в `docs/{ru,en}/USAGE.md`;
- новая функциональность — в `CHANGELOG.{ru,en}.md` и `RELEASE_NOTES.{ru,en}.md`;
- правки внесены сначала в `docs/ru/`, затем синхронно в `docs/en/`.
