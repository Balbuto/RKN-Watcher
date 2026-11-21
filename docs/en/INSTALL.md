# Installation

## System requirements

Supported systems:

- Debian 11 / 12
- Ubuntu 20.04 / 22.04 / 24.04

Required:

- root access;
- `systemd`;
- `iptables` + `ipset` + `nftables` (installed by the installer; the package, the `nft`
  binary and the loaded ruleset are verified before installation);
- `python3` — for `config_tool.py` and `geoip_apply.py`;
- internet access for the initial list download.

Optional:

- `ip6tables` — enables IPv6 filtering (`TSPUIPS6`, `GOVIPS6`, `GEOIP_ALLOW_IPS6`
  and the `*6` chains). Without it the IPv6 part is skipped and IPv4 keeps working;
- `iptables-legacy` / `iptables-nft` — when both backends exist, pick one with
  `NETFILTER_BACKEND` (see [configuration](CONFIGURATION.md)).

## Recommended method

```bash
git clone https://github.com/Balbuto/RKN-Watcher.git
cd RKN-Watcher
chmod +x installer.sh rkn-watcher.sh
sudo ./installer.sh
```

The interactive `installer.sh`:

1. checks that it is running as `root`;
2. checks dependencies (`apt` / `dpkg`);
3. installs missing packages (including `nftables`);
4. records which packages it installed itself;
5. verifies nftables: package, `nft` binary, readable ruleset, and which backend
   `iptables` uses (details in [INSTALLER](INSTALLER.md));
6. runs `rkn-watcher.sh install`.

The main script then:

1. creates directories under `/opt`, `/etc`, `/var/lib`, `/var/log`;
2. copies `rkn-watcher.sh`, the `lib/` modules, `config_tool.py` and `geoip_apply.py`
   into `/opt/rkn-watcher`;
3. creates the `rkn-watcher` command in `/usr/local/bin`;
4. creates `systemd` units (boot restore and update timer);
5. creates `settings.conf`, `whitelist.json`, `blacklist.json`;
6. downloads `TSPUBLOCK` and `GOVIPS`;
7. applies `iptables` / `ipset` rules.

## What is created on the system

### Executables

- `/opt/rkn-watcher/rkn-watcher.sh` — entry point (16 lines)
- `/opt/rkn-watcher/lib/*.sh` — modules: `config`, `common`, `firewall`, `snapshots`,
  `lists`, `services`, `ui`, `cli`
- `/opt/rkn-watcher/config_tool.py`
- `/opt/rkn-watcher/geoip_apply.py`
- `/usr/local/bin/rkn-watcher` — symlink to the entry point

### Configuration (`0600 root`)

- `/etc/rkn-watcher/settings.conf`
- `/etc/rkn-watcher/whitelist.json`
- `/etc/rkn-watcher/blacklist.json`

### State and cache

- `/var/lib/rkn-watcher/cache/lists/` — downloaded list cache (conditional GET)
- `/var/lib/rkn-watcher/cache/countries/` — ipdeny country zone cache
- `/var/lib/rkn-watcher/state/` — counters and set signatures
- `/var/lib/rkn-watcher/snapshots/` — rule snapshots before every `apply`/`update`
- `/var/lib/rkn-watcher/backups/` — `/etc/rkn-watcher` backups before code updates
- `/var/lib/rkn-watcher/locks/` — `flock` files

### Logs (rotated by logrotate)

- `/var/log/rkn-watcher/update.log`
- `/var/log/rkn-watcher/actions.log`
- `/var/log/rkn-watcher/geoip.log`

### systemd

- `rkn-watcher-boot.service` — restores rules at boot
- `rkn-watcher-update.service` + `rkn-watcher-update.timer` — list auto-update

## First start

```bash
sudo rkn-watcher            # interactive menu
sudo rkn-watcher status     # status
sudo rkn-watcher doctor     # environment and rule diagnostics
```

## Upgrading to v3.2.1

```bash
cd RKN-Watcher
git pull
sha256sum -c SHA256SUMS
sudo ./installer.sh install
```

Choose to preserve the current configuration when prompted. The upgrade also copies
`lib/`, so nothing extra is needed. See [migration](MIGRATION.md).

## Installing without git

Download into one directory:

- `installer.sh`
- `rkn-watcher.sh`
- `lib/` (all 8 modules)
- `config_tool.py`
- `geoip_apply.py`

Then run:

```bash
chmod +x installer.sh rkn-watcher.sh
sudo ./installer.sh
```

Without `lib/` the script stops with `Не найден каталог модулей lib/` — the entry
point cannot work without its modules.

## Removal

```bash
sudo ./installer.sh uninstall
```

Or:

```bash
sudo rkn-watcher uninstall
```

Only managed changes are removed: units, managed chains and sets (IPv4 and IPv6),
`/opt/rkn-watcher`, `/etc/rkn-watcher`, `/var/lib/rkn-watcher`,
`/var/log/rkn-watcher`, `/usr/local/bin/rkn-watcher`.
