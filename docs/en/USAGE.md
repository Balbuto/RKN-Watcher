# Usage

## Main commands

```bash
sudo rkn-watcher install                 # install / update the code
sudo rkn-watcher update                  # refresh TSPUBLOCK and GOVIPS and apply
sudo rkn-watcher apply                   # re-apply rules from the current config
sudo rkn-watcher apply --dry-run         # print the ruleset without applying
sudo rkn-watcher status                  # state (--json for monitoring)
sudo rkn-watcher doctor                  # environment and rule diagnostics
sudo rkn-watcher metrics                 # Prometheus text format
sudo rkn-watcher snapshot                # take a snapshot manually
sudo rkn-watcher snapshots               # list snapshots
sudo rkn-watcher rollback [STAMP]        # restore a snapshot
sudo rkn-watcher uninstall               # remove the application
sudo rkn-watcher --help | --version
```

Via the installer:

```bash
sudo ./installer.sh
sudo ./installer.sh install
sudo ./installer.sh uninstall
sudo ./installer.sh deps
sudo ./installer.sh status
sudo ./installer.sh nft      # nftables check: package, nft binary, ruleset, iptables backend
```

`status`, `metrics` and `doctor` also work without `root` (some checks are skipped and
marked as such in the output).

### Flags

| Flag | Command | Meaning |
|---|---|---|
| `--quiet` | `update` | minimal output, for systemd |
| `--dry-run` | `apply` | print the `iptables-restore` payload only |
| `--force` | `apply` | rebuild sets ignoring content signatures |
| `--json` | `status` | machine-readable output |
| `--yes` | `install` | non-interactive, keeps the current configuration |

## Lockout protection

```bash
sudo rkn-watcher allow-my-ip              # IP from $SSH_CONNECTION → allow list + apply
sudo rkn-watcher allow-my-ip 203.0.113.7  # manually (IPv4 or IPv6)
sudo rkn-watcher block-ip 198.51.100.0/24
sudo rkn-watcher unblock-ip 198.51.100.0/24
```

`block-ip`/`unblock-ip` add the entry to `blacklist.json` and re-apply rules
immediately.

Before enabling GeoIP the menu checks whether your SSH IP is in the allow list and
offers to add it.

## Netfilter backend

```bash
sudo rkn-watcher doctor | grep -i backend
```

`doctor` prints the configured `NETFILTER_BACKEND` value, the effective backend
`iptables` actually uses, and warns when they diverge — the usual cause of "rules were
applied but traffic is not filtered" (rules went to `iptables-nft` while you inspect
`iptables-legacy`).

Changing it:

```bash
sudo rkn-watcher          # Settings → 10) Netfilter backend (auto/legacy/nft)
```

or directly:

```bash
echo 'NETFILTER_BACKEND="legacy"' | sudo tee -a /etc/rkn-watcher/settings.conf
sudo rkn-watcher apply
```

## Snapshots and rollback

Before every `apply`/`update` the script stores `iptables-save`, `ip6tables-save` and
`ipset save` in `/var/lib/rkn-watcher/snapshots/<timestamp>/`.

```bash
sudo rkn-watcher snapshot            # take a snapshot manually
sudo rkn-watcher snapshots           # list with timestamps and sizes
sudo rkn-watcher rollback            # roll back to the last one
sudo rkn-watcher rollback 20260809-030000
```

Retention: the last `SNAPSHOT_KEEP` (10 by default) are never removed; anything older
than `SNAPSHOT_MAX_AGE_DAYS` (30 by default) is pruned automatically.

After losing SSH access, rolling back from the console/IPMI is a single command.

## Non-interactive mode

```bash
sudo rkn-watcher install --yes     # update the code, keep the current configuration
```

## Interactive menu

```bash
sudo rkn-watcher
```

Main menu:

1. Blocklists — enable/disable `TSPUBLOCK` and `GOVIPS`, update lists, show
   `iptables` / `ipset`;
2. GeoIP — enable/disable, countries, allow/deny IPs (IPv4 and IPv6) and ports;
3. Settings — `FILTER_PORTS`, `LOG_RST`, `AUTO_UPDATE`, port policy, snapshots,
   diagnostics, netfilter backend;
4. Status;
5. Logs;
6. Reinstall / update;
7. Uninstall;
8. Diagnostics.

Settings submenu:

```text
1) Change FILTER_PORTS
2) Toggle LOG_RST
3) Toggle AUTO_UPDATE
4) Re-apply rules
5) Port policy (geoip_only / strict)
6) Take a snapshot
7) Roll back the last snapshot
8) Diagnostics (doctor)
9) List snapshots
10) Netfilter backend (auto/legacy/nft)
0) Back
```

### GeoIP address input

Allow/deny IPs accept IPv4 **and** IPv6 addresses and CIDRs: `1.2.3.4`, `10.0.0.0/24`,
`2001:db8::1`, `2001:db8::/32`. The family is detected automatically. Use the menu or
`config_tool.py` for serialized changes; after a manual edit run
`sudo rkn-watcher apply`.

## Updating blocklists

```bash
sudo rkn-watcher update
```

Scheduled run — `rkn-watcher-update.timer`, daily at `03:00` with
`RandomizedDelaySec=1h` (spreads load on sources and on the xtables lock).

Data quality safeguards:

- conditional GET (`curl -z`): unchanged sources are not re-downloaded;
- set signatures: unchanged content does not rebuild the `ipset`;
- sanity gate: a sharply shrinking or growing list is not applied;
- a failed `ipset restore`/`swap` returns an error instead of a false success, the old
  set keeps working.

## Metrics

```bash
sudo rkn-watcher metrics > /var/lib/node_exporter/textfile/rkn-watcher.prom
sudo rkn-watcher status --json | jq
```

## Logs

```bash
sudo tail -n 100 /var/log/rkn-watcher/update.log
sudo tail -n 100 /var/log/rkn-watcher/actions.log
sudo tail -n 100 /var/log/rkn-watcher/geoip.log
```

Rotation lives in `/etc/logrotate.d/rkn-watcher`.

## Checking the timer

```bash
systemctl status rkn-watcher-update.timer
systemctl list-timers | grep rkn-watcher
```

## Checking rules and sets

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

# IPv6 (when ip6tables is installed)
sudo ip6tables -L INPUT -v -n
sudo ip6tables -L RKN_GEOIP_HOOK6 -v -n
sudo ip6tables -L TSPUBLOCK6 -v -n
sudo ipset list TSPUIPS6 | head -20
sudo ipset list GEOIP_ALLOW_IPS6 | head -20
sudo ipset list GEOIP_DENY_IPS6 | head -20
sudo ipset list GEOIP_COUNTRIES_ALLOW6 | head -20
```

If the backend is not `auto`, use the matching tools (`iptables-legacy`,
`iptables-nft`) — otherwise you will see empty chains.
