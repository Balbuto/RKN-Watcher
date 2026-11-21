# Release Notes — RKN Watcher v3.2.1

## Overview

`v3.2.1` closes every remaining recommendation of the v3.1 external audit except
verifying signatures of third-party list sources (outside our control — the repos are
not ours). Default behaviour and the configuration format are unchanged.

## What's new

### Modular layout

The 2050-line monolith is split into modules; the entry point `rkn-watcher.sh` is
16 lines:

```text
lib/config.sh     paths, constants, module loading
lib/common.sh     output, logs, settings.conf, validation, helper/lib installation
lib/firewall.sh   ipset, RST rules, netfilter backend selection
lib/snapshots.sh  snapshots, rotation, rollback
lib/lists.sh      list download, sanitizing, sanity gate
lib/services.sh   systemd, logrotate, install/uninstall
lib/ui.sh         status, metrics, doctor, menu
lib/cli.sh        argument parsing and main()
```

Modules are installed into `/opt/rkn-watcher/lib` automatically.

### IPv6 for allow/deny lists

`whitelist.ips` and `blacklist.ips` accept IPv4 **and** IPv6. Addresses are split by
family: IPv6 goes to `GEOIP_ALLOW_IPS6`, `GEOIP_DENY_IPS6`, `GEOIP_COUNTRIES_ALLOW6`
(`family inet6`) and is enforced in `ip6tables` through the `RKN_GEOIP_HOOK6` chain.
Previously IPv6 entries were rejected, leaving the allow list ineffective for IPv6
traffic on dual-stack hosts.

### Netfilter backend selection

New key `NETFILTER_BACKEND=auto|legacy|nft`. `doctor` reports both the configured and
the effective backend and warns on divergence — the most common cause of "rules applied
but not working".

### nftables verification during installation

The installer no longer assumes nftables is present. It checks the `nftables` package,
the `nft` binary, ruleset readability, and reports which backend `iptables` uses (`nft`
or `legacy`). An empty ruleset with an inactive `nftables.service` is a common cause of
"rules vanished after reboot" — now it surfaces immediately. Standalone check:
`sudo ./installer.sh nft`.

### Snapshots

Age-based rotation: `SNAPSHOT_MAX_AGE_DAYS` (30 by default) and `SNAPSHOT_KEEP`
(10 by default — the last N are never removed). New command
`sudo rkn-watcher snapshots` and a menu entry listing snapshots with sizes.

### Other

- if a key is duplicated in `settings.conf`, the last value wins (as in shell) and
  `doctor` lists duplicates;
- `config_tool.py` accepts IPv6; malformed addresses are explicit errors;
- settings menu entries are ordered (8 — diagnostics, 9 — snapshots, 10 — backend).

## Operations

```bash
sudo rkn-watcher snapshots                 # list snapshots
sudo rkn-watcher doctor | grep -i backend  # which backend is really in use
sudo ip6tables -L RKN_GEOIP_HOOK6 -v -n    # IPv6 rules
sudo rkn-watcher apply --dry-run           # what will be applied
```

## Compatibility

- `settings.conf` and JSON configs from v3.1/v3.2 are read as-is; new keys have defaults;
- set and chain names are unchanged, only `*6` variants were added;
- when upgrading **manually by copying files**, do not forget the `lib/` directory
  (`installer.sh` copies it for you).

## Verified

- 24 mock tests including new regressions: IPv6 in allow/deny and `ip6tables`, malformed
  address rejection, backend selection/validation, snapshot rotation;
- `bash -n`, `shellcheck -S warning` (0 warnings), `pyflakes`, `py_compile`;
- `./release.sh --check` — 47-file manifest verified;
- rootless stand run: `install` → `update` → `apply` (`auto` and `legacy`) →
  `snapshots` → `doctor`.

## Upgrade

```bash
cd RKN-Watcher
git pull
sha256sum -c SHA256SUMS
sudo ./installer.sh install
sudo rkn-watcher apply --dry-run
sudo rkn-watcher doctor
sudo rkn-watcher apply
```
