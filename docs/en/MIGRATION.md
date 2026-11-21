# Migration to v3.2.1

## At a glance

| Case | Action |
|---|---|
| upgrade via `installer.sh` | nothing to do, `lib/` is copied automatically |
| manual upgrade (file copy) | **copy the `lib/` directory** into `/opt/rkn-watcher/` |
| IPv6 entries in JSON | they work now, no need to remove them |
| new keys | `NETFILTER_BACKEND`, `SNAPSHOT_KEEP`, `SNAPSHOT_MAX_AGE_DAYS` — optional, defaults apply |
| old configs | compatible as-is |

## What changed in v3.2.1

- **modular layout**: the entry point `rkn-watcher.sh` is 16 lines; logic lives in
  `lib/common.sh`, `lib/firewall.sh`, `lib/snapshots.sh`, `lib/lists.sh`,
  `lib/services.sh`, `lib/ui.sh`, `lib/cli.sh`, constants in `lib/config.sh`.
  A standalone script without `lib/` will not run — it exits with
  `Не найден каталог модулей lib/`;
- **IPv6 for allow/deny lists**: entries are split into the `*6` sets and enforced in
  `ip6tables` (`RKN_GEOIP_HOOK6`). IPv6 entries that used to be rejected are now
  applied — restore them if you deleted them earlier;
- **`NETFILTER_BACKEND`** (`auto`/`legacy`/`nft`): explicit backend selection with
  effective-state verification in `doctor`;
- **snapshot rotation**: `SNAPSHOT_MAX_AGE_DAYS` (30) and `SNAPSHOT_KEEP` (10), plus
  the new `rkn-watcher snapshots` command;
- `get_setting` takes the last occurrence of a duplicated key (like shell) and `doctor`
  warns about duplicates.

## Recommended upgrade sequence

```bash
cd RKN-Watcher
git pull
sha256sum -c SHA256SUMS
sudo ./installer.sh install          # keep the existing configuration
sudo rkn-watcher apply --dry-run     # inspect the new ruleset
sudo rkn-watcher doctor              # environment, backend, rule consistency
sudo rkn-watcher apply
sudo rkn-watcher status
```

## Manual upgrade (without installer.sh)

```bash
sudo install -d -m 0755 /opt/rkn-watcher/lib
sudo install -m 0755 rkn-watcher.sh /opt/rkn-watcher/
sudo install -m 0755 lib/*.sh /opt/rkn-watcher/lib/
sudo install -m 0755 config_tool.py geoip_apply.py /opt/rkn-watcher/
sudo rkn-watcher apply
```

## What to verify after migration

```bash
sudo rkn-watcher status
sudo rkn-watcher doctor
sudo iptables -L INPUT -v -n
sudo ipset list TSPUIPS | head -3
sudo ipset list GOVIPS | head -3
sudo ipset list GEOIP_COUNTRIES_ALLOW | head -3
# IPv6 (when ip6tables is installed)
sudo ip6tables -L RKN_GEOIP_HOOK6 -v -n
sudo ipset list GEOIP_ALLOW_IPS6 | head -3
```

## Migration to v3.2

### What changed in v3.2

The v3.1 audit found four bugs, fixed in v3.2:

1. **fail-open in bash** — `ENABLE_TSPUBLOCK="true"`/`"1"`/`"on"` silently disabled
   blocking. Values are normalized now and invalid ones make `apply` fail.
2. **lockout risk** — `lo` and `ESTABLISHED,RELATED` were added to the GeoIP hook.
3. **deny/allow ports did not work when `FILTER_PORTS ≠ all`** — the `RKN_DENY` stage
   was introduced.
4. **`install` from `/usr/local/bin/rkn-watcher` failed** — helper paths are resolved
   via `readlink -f` and also looked up in `/opt/rkn-watcher`.

New chains: `RKN_DENY`, `RKN_PROTECT`; new sets: `TSPUIPS6`, `GOVIPS6` (when
`ip6tables` is installed). Old chains and sets keep their names.

### New PORT_POLICY key

Default is `PORT_POLICY=geoip_only` — behaviour compatible with v3.1 (GeoIP filters the
ports from `FILTER_PORTS`, the rest stay open). For "only `FILTER_PORTS` are reachable":

```bash
echo 'PORT_POLICY="strict"' | sudo tee -a /etc/rkn-watcher/settings.conf
sudo rkn-watcher apply
```

### When a list changes sharply

The sanity gate refuses lists that shrank more than 2x or grew more than 5x.
Intentional override: `sudo RKN_ALLOW_LIST_SHRINK=1 rkn-watcher update`.

## Migration from pre-v3 releases

Older versions had these problems:

- `ipset` was cleared before a new list was downloaded successfully;
- repeated applies accumulated duplicate `iptables` rules;
- `cron` and a background daemon conflicted;
- user input was handled partially unsafely;
- uninstall removed global firewall files;
- country-based GeoIP was advertised but not enforced as a real country filter.

v3 introduced the current atomic update, systemd, and CIDR-filtering design.
Since v3.2.1 IPv6 entries are accepted instead of rejected.

## Recommended path from v1/v2

### Option 1. Upgrade an existing installation

```bash
cd RKN-Watcher
git pull
sudo ./installer.sh install
```

Choose to preserve the current configuration, then run:

```bash
sudo rkn-watcher apply
sudo rkn-watcher status
```

### Option 2. Clean install

1. remove the old version (`sudo ./installer.sh uninstall`);
2. install the current version with `sudo ./installer.sh`;
3. migrate allow/deny entries (IPv4 and IPv6) and country codes;
4. review the country list before enabling GeoIP.

## Verifying release files

```bash
sha256sum -c SHA256SUMS
```
