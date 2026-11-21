# RKN Watcher v3.2.1 Documentation

Единственный источник документации — `docs/ru/` и `docs/en/`.
Правило репозитория: правки сначала в `docs/ru/`, затем синхронно в `docs/en/`.
Single source of truth is `docs/ru/` + `docs/en/`; edit Russian first, then mirror to English.

## Русская версия
- [Установка](ru/INSTALL.md)
- [Интерактивный установщик](ru/INSTALLER.md)
- [Использование](ru/USAGE.md)
- [Конфигурация](ru/CONFIGURATION.md)
- [Миграция](ru/MIGRATION.md)
- [Решение проблем](ru/TROUBLESHOOTING.md)
- [Безопасность](ru/SECURITY.md)

## English version
- [Installation](en/INSTALL.md)
- [Interactive installer](en/INSTALLER.md)
- [Usage](en/USAGE.md)
- [Configuration](en/CONFIGURATION.md)
- [Migration](en/MIGRATION.md)
- [Troubleshooting](en/TROUBLESHOOTING.md)
- [Security](en/SECURITY.md)

## Что нового в v3.2.1 / What's new in v3.2.1

| Возможность | Где описано |
|---|---|
| модули `lib/*.sh`, точка входа 16 строк | [INSTALL](ru/INSTALL.md), [MIGRATION](ru/MIGRATION.md) |
| IPv6 для allow/deny-списков | [CONFIGURATION](ru/CONFIGURATION.md), [SECURITY](ru/SECURITY.md) |
| `NETFILTER_BACKEND=auto\|legacy\|nft` | [CONFIGURATION](ru/CONFIGURATION.md), [TROUBLESHOOTING](ru/TROUBLESHOOTING.md) |
| ротация снапшотов, `rkn-watcher snapshots` | [USAGE](ru/USAGE.md), [CONFIGURATION](ru/CONFIGURATION.md) |
