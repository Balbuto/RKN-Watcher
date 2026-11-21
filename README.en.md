<img width="1536" height="1024" alt="image" src="https://github.com/user-attachments/assets/24fe2731-5dda-4342-9578-bd9e6f4331dd" />


# RKN Watcher v3.2.1

RKN Watcher is a set of scripts for Debian/Ubuntu Linux servers that:

- downloads and updates `TSPUBLOCK` and `GOVIPS` lists;
- applies filtering with `iptables` + `ipset`;
- supports country-based filtering plus allow/deny IP and port rules;
- performs atomic list updates without losing the active set on network failure;
- uses a `systemd timer` instead of the old `cron + daemon polling` model.

## Highlights of v3.1

- keeps the v3 atomic `ipset` update and duplicate-rule protections;
- protects the complete JSON configuration read-modify-write cycle with a file lock, so concurrent edits do not lose entries;
- interprets legacy boolean values such as `"false"` safely instead of accidentally enabling GeoIP;
- rejects unsupported entries consistently (IPv6 was rejected back then; since v3.2.1 it is supported);
- validates the checksum manifest in GitHub Actions and documents checksum verification before publishing;
- expands mock coverage for concurrent configuration edits, boolean normalization, and IPv6 rejection.

## Key changes in v3.2.1

- modular layout: `lib/*.sh` instead of a 2050-line monolith;
- IPv6 support for allow/deny lists (`*6` sets, `RKN_GEOIP_HOOK6` chain in `ip6tables`);
- `NETFILTER_BACKEND=auto|legacy|nft` with `doctor` verification;
- age-based snapshot rotation and `rkn-watcher snapshots`.

## Key changes in v3.2

- **fail-open fixed**: legacy booleans in `settings.conf` (`"true"`, `"1"`, `"on"`) no longer silently disable blocking; invalid values are hard errors;
- **no more self-lockout**: `RKN_GEOIP_HOOK` now returns for `-i lo` and `conntrack ESTABLISHED,RELATED`; new `allow-my-ip` command and an SSH-IP prompt before enabling GeoIP;
- **allow/deny ports always work**: denials moved into `RKN_DENY`, independent of `FILTER_PORTS`;
- **atomic apply**: a single `iptables-restore` instead of a chain of `iptables -A`;
- IPv6 blocking (`TSPUIPS6`/`GOVIPS6`), `PORT_POLICY=strict`, list sanity gate, conditional GET, `doctor`/`metrics`/`status --json`/`--dry-run`/`snapshot`/`rollback`, logrotate, systemd hardening, CI checks.
- `install`/`update` through the `/usr/local/bin` symlink now works.

## Repository layout

```text
RKN-Watcher/
├── installer.sh
├── release.sh
├── rkn-watcher.sh          # 16-line entry point
├── lib/                    # config, common, firewall, snapshots, lists, services, ui, cli
├── config_tool.py
├── geoip_apply.py
├── README.ru.md / README.en.md
├── CHANGELOG.ru.md / CHANGELOG.en.md
├── RELEASE_NOTES.ru.md / RELEASE_NOTES.en.md
├── PUBLISHING.ru.md / PUBLISHING.en.md
├── docs/
│   ├── ru/
│   └── en/
└── tests/
```

## Quick start

```bash
git clone https://github.com/Balbuto/RKN-Watcher.git
cd RKN-Watcher
chmod +x installer.sh rkn-watcher.sh
sudo ./installer.sh
```

The installer:
- checks that it runs as `root`;
- checks required dependencies;
- installs missing packages;
- launches the main interactive installation flow;
- supports full removal of all managed changes.

## Main commands

### Via installer
```bash
sudo ./installer.sh
sudo ./installer.sh install
sudo ./installer.sh uninstall
sudo ./installer.sh deps
sudo ./installer.sh status
```

### Via main script
```bash
sudo ./rkn-watcher.sh install
sudo ./rkn-watcher.sh update
sudo ./rkn-watcher.sh apply
sudo ./rkn-watcher.sh status
sudo ./rkn-watcher.sh uninstall
```

After installation, the following shortcut is also created:

```bash
sudo rkn-watcher
```

## Supported environment

- Debian 11 / 12
- Ubuntu 20.04 / 22.04 / 24.04
- IPv4 and IPv6 (IPv6 activates automatically when `ip6tables` is present)
- `legacy` and `nft` netfilter backends (selected via `NETFILTER_BACKEND`)
- `root` privileges are required

## Things to know about v3.2.1

- **Modules.** The script is an entry point plus the `lib/` directory. When upgrading
  manually, copy `lib/` too; `installer.sh` and `rkn-watcher install` do it for you.
- **IPv6.** Allow/deny addresses and CIDRs are accepted for both families and enforced
  in `ip6tables`; without `ip6tables` the IPv6 part is skipped with a warning.
- **Backend.** If both `iptables-legacy` and `iptables-nft` exist, set the intended one
  and verify with `sudo rkn-watcher doctor | grep -i backend`.
- **nftables.** The installer verifies the `nftables` package, the `nft` binary and
  ruleset readability, and shows which backend `iptables` uses; it stops on failure.
  Standalone: `sudo ./installer.sh nft`.
- **Snapshots.** The last `SNAPSHOT_KEEP` (10) and everything younger than
  `SNAPSHOT_MAX_AGE_DAYS` (30 days) are kept. Roll back with `sudo rkn-watcher rollback`.

## Data sources

- TSPU / Skipa CIDR: `https://github.com/tread-lightly/CyberOK_Skipa_ips`
- GOVIPS / blacklist-v4.ipset: `https://github.com/C24Be/AS_Network_List`
- Country CIDR: `https://www.ipdeny.com/ipblocks/`

These sources are third-party and unsigned — a known limitation (see
[Security](docs/en/SECURITY.md)), partially mitigated by the list sanity gate.

## Documentation

- [Installation](docs/en/INSTALL.md)
- [Interactive installer](docs/en/INSTALLER.md)
- [Usage](docs/en/USAGE.md)
- [Configuration](docs/en/CONFIGURATION.md)
- [Migration](docs/en/MIGRATION.md)
- [Troubleshooting](docs/en/TROUBLESHOOTING.md)
- [Security](docs/en/SECURITY.md)

## License

MIT. See [LICENSE](LICENSE).
