# Configuration

## settings.conf

File:

```text
/etc/rkn-watcher/settings.conf
```

Shipped version: `3.2.1`. Full key list with defaults:

```ini
ENABLE_TSPUBLOCK="y"
ENABLE_GOVIPS="y"
FILTER_PORTS="all"
PORT_POLICY="geoip_only"
NETFILTER_BACKEND="auto"
LOG_RST="n"
AUTO_UPDATE="y"
SNAPSHOT_KEEP="10"
SNAPSHOT_MAX_AGE_DAYS="30"
```

Boolean keys (`LOG_RST`, `AUTO_UPDATE`, `ENABLE_TSPUBLOCK`, `ENABLE_GOVIPS`) accept
`y/n`, `yes/no`, `true/false`, `1/0`, `on/off`. Any other value is a configuration
error: `apply`/`update` exit 1 and no rules are applied (fail-closed).

If a key appears more than once, the **last** value wins (as in shell); `doctor` prints
a warning listing duplicate keys.

### `FILTER_PORTS`

Scope of country-based GeoIP: which TCP ports the country filter applies to.
Deny/allow lists (`blacklist.json`/`whitelist.json`) are independent of this key.

```ini
FILTER_PORTS="all"
FILTER_PORTS="443"
FILTER_PORTS="80,443,8443"
```

### `PORT_POLICY`

```ini
PORT_POLICY="geoip_only"   # default: GeoIP filters FILTER_PORTS, other ports stay open
PORT_POLICY="strict"       # only FILTER_PORTS are reachable, everything else is dropped
```

`strict` is a port whitelist mode: `-p tcp --dport <port> RETURN` for every port in
`FILTER_PORTS` (TCP and UDP), then `DROP`.

With GeoIP enabled and `FILTER_PORTS="all"`, `apply` warns about lockout risk: the
country filter then applies to every port and only established connections and the
allow list can save you.

### `NETFILTER_BACKEND`

```ini
NETFILTER_BACKEND="auto"     # as configured on the system (default)
NETFILTER_BACKEND="legacy"   # iptables-legacy / ip6tables-legacy
NETFILTER_BACKEND="nft"      # iptables-nft / ip6tables-nft
```

Needed on hosts where both `legacy` and `nft` tools exist (after a distro migration,
next to docker or Kubernetes). The choice applies to the bash part (`iptables`,
`ip6tables`, `iptables-restore`, …), to `geoip_apply.py`, and to snapshot/rollback.

- a missing binary produces a warning and falls back to plain `iptables`;
- an unknown value (`bogus`) is a configuration error;
- `doctor` shows the configured and effective values and warns on divergence;
- `installer.sh` verifies `nftables` itself before installing (package, `nft` binary,
  readable ruleset) and reports which backend `iptables` uses
  (see [installer](INSTALLER.md)).

### `SNAPSHOT_KEEP` and `SNAPSHOT_MAX_AGE_DAYS`

```ini
SNAPSHOT_KEEP="10"           # the last N snapshots are never removed
SNAPSHOT_MAX_AGE_DAYS="30"   # anything older than 30 days is pruned
```

A snapshot is taken before every `apply`/`update` and on demand (`snapshot`):
`iptables-save`, `ip6tables-save`, `ipset save` into
`/var/lib/rkn-watcher/snapshots/<timestamp>/`. List them with `rkn-watcher snapshots`.

### `LOG_RST`

Enables/disables logging of RST drops for `TSPUBLOCK` and `GOVIPS`.

```ini
LOG_RST="y"
LOG_RST="n"
```

Dropped packets go to the kernel log (`LOG` target with
`--log-prefix "TSPUBLOCK: "` / `"GOVIPS: "`):

```bash
sudo dmesg -T | grep -E 'TSPUBLOCK|GOVIPS'
sudo journalctl -k | grep -E 'TSPUBLOCK|GOVIPS'
```

Rate-limited: `-m limit --limit 5/min --limit-burst 10`.

### `AUTO_UPDATE`

Enables/disables the `systemd timer` `rkn-watcher-update.timer`.

### `ENABLE_TSPUBLOCK` / `ENABLE_GOVIPS`

Enables/disables the corresponding blocklist (`TSPUBLOCK` / `GOVIPS`).

## whitelist.json

```text
/etc/rkn-watcher/whitelist.json
```

```json
{
  "enabled": true,
  "countries": ["RU", "FI"],
  "ips": ["1.2.3.4", "10.0.0.0/24", "2001:db8::/32"],
  "ports": [22, 443]
}
```

Fields:

- `enabled` — whether GeoIP filtering is enabled (JSON boolean);
- `countries` — allowed country codes (ISO-3166 alpha-2, upper case);
- `ips` — allowed addresses/CIDRs: **IPv4 and IPv6**;
- `ports` — allowed TCP ports.

`enabled` must be a JSON boolean: `true` or `false`. For compatibility the helper also
reads common legacy values (`"true"`, `"false"`, `1`, `0`) but always writes a boolean.

Addresses are split by family automatically: IPv4 → `GEOIP_ALLOW_IPS`,
IPv6 → `GEOIP_ALLOW_IPS6` (`family inet6`). A malformed entry (`2001:db8:::1`) is a
configuration error, not a silent skip.

## blacklist.json

```text
/etc/rkn-watcher/blacklist.json
```

```json
{
  "ips": ["203.0.113.5", "198.51.100.0/24", "2001:db8:dead::/48"],
  "ports": [25, 3389]
}
```

Fields:

- `ips` — denied addresses/CIDRs (IPv4 and IPv6 → `GEOIP_DENY_IPS`, `GEOIP_DENY_IPS6`);
- `ports` — denied TCP ports.

## Rule evaluation order

IPv4: `INPUT → RKN_GEOIP_HOOK` (comment `rkn-watcher-geoip-hook`), plus `-j TSPUBLOCK`
and `-j GOVBLOCK` hooks.

Inside `RKN_GEOIP_HOOK`:

1. `-i lo` → `RETURN` — loopback is never filtered;
2. `-m conntrack --ctstate ESTABLISHED,RELATED` → `RETURN` — established sessions
   (including your SSH session) survive `apply`;
3. `RKN_DENY` (independent of `FILTER_PORTS`): deny IP → `DROP`, deny ports → `DROP`;
4. `GEOIP_DROP` (ports from `FILTER_PORTS`): allow IP → `RETURN`, allow ports → `RETURN`,
   allow countries → `RETURN`, otherwise `DROP`;
5. `RKN_PROTECT` (only with `PORT_POLICY=strict`): everything outside `FILTER_PORTS`
   → `DROP`.

If the country list is empty, country-based drop is not applied and the stage ends with
`RETURN`.

The whole ruleset is assembled into one `iptables-restore` payload and applied
atomically; `rkn-watcher apply --dry-run` prints exactly what will be applied.

## IPv6

| Purpose | Sets | Chains (`ip6tables`) |
|---|---|---|
| TSPU RST blocking | `TSPUIPS6` | `TSPUBLOCK6` |
| GOVIPS | `GOVIPS6` | `GOVBLOCK6` |
| allow IPs | `GEOIP_ALLOW_IPS6` | `RKN_GEOIP_HOOK6` |
| deny IPs | `GEOIP_DENY_IPS6` | `RKN_DENY` (inside the hook) |
| countries | `GEOIP_COUNTRIES_ALLOW6` | `GEOIP_DROP` (inside the hook) |

The logic inside `RKN_GEOIP_HOOK6` mirrors IPv4 (`lo`, `ESTABLISHED,RELATED`, deny,
allow, countries, strict port policy). The hook is created whenever at least one IPv6
stage exists: allow/deny list, country filter, or `PORT_POLICY=strict`.

Without `ip6tables` the IPv6 part is skipped with a warning and IPv4 keeps working.
Check with `sudo rkn-watcher doctor` and `sudo ip6tables -L RKN_GEOIP_HOOK6 -v -n`.

## State files

```text
/var/lib/rkn-watcher/state/tspu_count.txt   # entries in the last successful update
/var/lib/rkn-watcher/state/gov_count.txt
/var/lib/rkn-watcher/state/sig.*            # set signatures (including *.ips6, *.countries)
/var/lib/rkn-watcher/snapshots/<stamp>/     # iptables-save + ip6tables-save + ipset save
/var/lib/rkn-watcher/cache/lists/           # downloaded list cache (conditional GET via -z)
/var/lib/rkn-watcher/cache/countries/       # ipdeny country zone cache
/var/lib/rkn-watcher/backups/               # /etc/rkn-watcher backups before code updates
```

## List sanity gate

A new list that shrinks below 50% or grows above 500% of the previous size is not
applied (the old set keeps working) and the reason is logged to `update.log`.
Intentional changes: `sudo RKN_ALLOW_LIST_SHRINK=1 rkn-watcher update`.

## Safe editing with the helper tool

`config_tool.py` holds one advisory lock for the full read-modify-write operation, so use
it instead of simultaneous manual edits when multiple administrators or automation jobs
manage the configuration.

```bash
sudo /opt/rkn-watcher/config_tool.py add-country FI
sudo /opt/rkn-watcher/config_tool.py remove-country FI
sudo /opt/rkn-watcher/config_tool.py add-ip 1.2.3.4
sudo /opt/rkn-watcher/config_tool.py add-ip 2001:db8::1     # IPv6 is accepted too
sudo /opt/rkn-watcher/config_tool.py add-port 443
sudo /opt/rkn-watcher/config_tool.py add-deny-ip 203.0.113.5
sudo /opt/rkn-watcher/config_tool.py add-deny-port 25
sudo /opt/rkn-watcher/config_tool.py show all
```

After manual config edits, run:

```bash
sudo rkn-watcher apply
```
