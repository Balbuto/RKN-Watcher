# Security and limitations

## Security fixes in v3.2.1

- **IPv6 for allow/deny lists**: addresses are split by family, IPv6 goes to
  `family inet6` sets and to a dedicated `RKN_GEOIP_HOOK6` chain. Previously IPv6
  entries were rejected outright, so on a dual-stack host the allow list did not
  actually protect IPv6 traffic;
- **explicit netfilter backend** (`NETFILTER_BACKEND`): rules written through
  `iptables-nft` are no longer inspected through `iptables-legacy` (and vice versa);
  divergence is reported by `doctor` and can be configured;
- **age-based snapshot rotation**: old snapshots are pruned (30 days by default) so the
  directory cannot grow without bound; the last `SNAPSHOT_KEEP` are always kept;
- **deterministic `settings.conf` parsing**: the last occurrence of a duplicated key
  wins and `doctor` lists duplicates, ruling out "security key set lower in the file
  but not effective";
- **malformed addresses** in allow/deny lists are configuration errors (fail-closed)
  instead of silently skipped entries.

## Security fixes in v3.2

- **fail-closed instead of fail-open**: an invalid boolean in `settings.conf` is an
  apply error instead of silently disabling blocking;
- **lockout protection**: `RKN_GEOIP_HOOK` returns traffic for `lo` and
  `ESTABLISHED,RELATED`; when GeoIP is enabled the script offers to add the current
  SSH IP to the allow list (`rkn-watcher allow-my-ip`);
- **snapshots before every apply** (`/var/lib/rkn-watcher/snapshots/`) plus the
  `rollback` command — console recovery in one command;
- **atomic rule application** via a single `iptables-restore`: no half-applied ruleset
  and no `xtables lock` races (`-w` everywhere);
- **list sanity gate**: a compromised or broken upstream that collapses the list does
  not disable blocking or cause mass `DROP`s;
- **systemd hardening**: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`,
  `PrivateTmp`, `CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW`;
- **configuration permissions**: `settings.conf`, `whitelist.json`, `blacklist.json` are
  `0600 root`; backups `0600`; log rotation `0640 root:root`;
- **rotated logs** (`/etc/logrotate.d/rkn-watcher`), `truncate` instead of `: >`.

## Security fixes in v3.1

- user input is not interpolated directly into inline Python code;
- JSON configuration is written atomically via a temporary file and `os.replace()`;
- one advisory file lock covers the full configuration read-modify-write operation, so
  concurrent edits do not lose changes;
- legacy boolean values are parsed explicitly, so `"false"` is not treated as truthy;
- concurrent `update` and `apply` operations are serialized with `flock`;
- `ipset` updates are atomic through a temporary set and `swap`;
- the checksum manifest is rebuilt by the release script and verified by
  `sha256sum -c` in GitHub Actions.

## Known limitations

- **list sources are not signed.** TSPU/GOVIPS are fetched over HTTPS from third-party
  repositories (`tread-lightly/CyberOK_Skipa_ips`, `C24Be/AS_Network_List`) that
  publish no signatures; upstream compromise remains a risk. It is partially mitigated
  by the sanity gate (a list that halved or grew 5x is not applied);
- **without `ip6tables`** IPv6 traffic is not filtered — `doctor` states this explicitly
  (`ip6tables: нет (IPv6 не защищён)`);
- **country GeoIP is CIDR filtering**, not a MaxMind database: it relies on published
  ipdeny country block lists;
- **`PORT_POLICY=geoip_only` (default)** filters only `FILTER_PORTS`; "filter
  everything" scenarios require an explicit `PORT_POLICY=strict`;
- **not recommended** on hosts where `iptables` is fully rewritten by another system
  (orchestrator, panel firewall manager, CM system). Docker is safe: the hook stays in
  `INPUT` while docker rules live in `FORWARD`/`NAT`, but `doctor` still warns.

## Important operational notes

### The scripts run as root

This is required to manage `iptables`, `ipset`, and `systemd`. Before enabling GeoIP on
a remotely administered host, review the country, allow, and deny rules and run
`sudo rkn-watcher allow-my-ip` in advance.

### Country-based GeoIP depends on an external CIDR source

The project uses `ipdeny.com`. If the source is unavailable:

- cached data is used if present (`/var/lib/rkn-watcher/cache/countries/`);
- without a cache that country set cannot be refreshed (the old set keeps working).
