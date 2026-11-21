# Changelog

## v3.2.1 — 2026-11-21

Closes every audit recommendation except source-signature verification (outside our control).

### Architecture

- the 2050-line monolith is split into `lib/config.sh`, `lib/common.sh`, `lib/firewall.sh`,
  `lib/snapshots.sh`, `lib/lists.sh`, `lib/services.sh`, `lib/ui.sh`, `lib/cli.sh`;
  the entry point is 16 lines;
- modules are installed into `/opt/rkn-watcher/lib` by `install` (`copy_lib_modules`);
- the test stand assembles `lib/*.sh` into a single library, so tests cover exactly the
  code that ships.

### IPv6 for allow/deny lists

- `whitelist.ips` / `blacklist.ips` accept IPv4 **and** IPv6, split automatically;
- IPv6 entries go to `GEOIP_ALLOW_IPS6`, `GEOIP_DENY_IPS6`, `GEOIP_COUNTRIES_ALLOW6`
  (`family inet6`) and are enforced in `ip6tables` via the `RKN_GEOIP_HOOK6` chain;
- country sets from ipdeny keep both families.

### netfilter backend

- new `NETFILTER_BACKEND=auto|legacy|nft` selects `iptables-legacy`/`iptables-nft`
  (and the `ip6tables` counterparts) in both the bash part and `geoip_apply.py`;
- `doctor` reports the configured and effective backend; unknown values are errors.

### nftables verification in the installer

- `installer.sh` now verifies before installing: the `nftables` package is present
  (installed automatically when missing), the `nft` binary is available,
  `nft list ruleset` succeeds (kernel with `nf_tables`, `CAP_NET_ADMIN` held), and the
  ruleset is not empty; with an empty ruleset and rules in `/etc/nftables.conf` it offers
  to start `nftables.service`;
- the installer reports which backend `iptables` uses (`nft` or `legacy`) and suggests
  `NETFILTER_BACKEND="nft"` when nft is required;
- new `sudo ./installer.sh nft` command and menu entry "5) Check nftables";
- `nftables` added to the installer's required dependencies and to the manifest of
  packages it installed.

### Snapshots

- age- and count-based rotation (`SNAPSHOT_MAX_AGE_DAYS`, `SNAPSHOT_KEEP`);
- new `rkn-watcher snapshots` command and menu entry.

### Compatibility and minor changes

- `settings.conf` and JSON configs from v3.1/v3.2 are read as-is; the new keys
  (`NETFILTER_BACKEND`, `SNAPSHOT_KEEP`, `SNAPSHOT_MAX_AGE_DAYS`) have defaults;
- a duplicated key in `settings.conf` uses the last value (as in shell) and `doctor`
  lists the duplicates;
- settings menu entries are ordered: 8 — diagnostics, 9 — snapshots, 10 — backend.

### Release packaging

- `release.sh` now builds `.zip` in addition to `.tar.gz`, plus per-archive checksums
  (`*.sha256`);
- archives are **complete**: `.github/workflows/tests.yml` is no longer excluded, which
  used to break `sha256sum -c SHA256SUMS` right after unpacking (`FAILED open or read`);
- modes (`*.sh` → `0755`, the rest `0644`) and owner `0/0` are normalized inside archives;
- `.gitattributes` added (LF for scripts and text) so permissions and line endings do not
  depend on how files were obtained;
- `installer.sh --help/--version` works without root.

### Tests

New regressions: IPv6 allow/deny and `ip6tables`, malformed addresses, IPv6 in
`config_tool.py`, backend selection and rejection of unknown values, age-based snapshot
rotation. 24 checks in total, `All tests passed.` The mock `ip6tables` now keeps separate
state, so v4/v6 rules can no longer be mixed silently.

### Documentation

`README.ru/en`, `docs/ru/*`, `docs/en/*`, `PUBLISHING.ru/en`, `RELEASE_NOTES.ru/en` and
`tests/README.*` fully updated: modules, IPv6, `NETFILTER_BACKEND`, snapshot rotation, the
`snapshots` command, backend-mismatch diagnostics, and a "Known limitations" section.

## v3.2.0 — 2026-11-21

### Fixed (from the v3.1 audit)

- **fail-open**: legacy booleans (`"true"`, `"1"`, `"on"`) no longer silently disable
  blocking; invalid values are hard errors and rules are left untouched;
- **self-lockout risk**: `-i lo -j RETURN` and `conntrack ESTABLISHED,RELATED -j RETURN`
  added to the GeoIP hook, plus an SSH-IP prompt and the `allow-my-ip` command;
- **allow/deny ports were unreachable when `FILTER_PORTS ≠ all`**: denials moved into the
  independent `RKN_DENY` stage;
- **country filtering silently left other ports open**: `FILTER_PORTS` semantics documented
  and extended with `PORT_POLICY=geoip_only|strict`;
- **`install`/`update` via the `/usr/local/bin` symlink always failed**: paths are resolved
  with `readlink -f` and helper scripts are also looked up in `/opt/rkn-watcher`;
- **`ipset restore`/`swap` failures were masked as success**: `shopt -s inherit_errexit`
  plus explicit return-code checks and error reasons in `update.log`;
- **`SHA256SUMS` was stale and CI never verified it**: regenerated manifest, added
  `sha256sum -c` and `shellcheck` steps;
- **`normalize_existing_json_files` was a no-op**: new `config_tool.py normalize` that
  really rewrites files with `0600` permissions.

### Added

- atomic ruleset application via a single `iptables-restore`, `-w` on every call;
- IPv6 blocking (`TSPUIPS6`/`GOVIPS6`, `TSPUBLOCK6`/`GOVBLOCK6`) when `ip6tables` exists;
- commands: `doctor`, `metrics`, `status --json`, `apply --dry-run`, `snapshot`, `rollback`,
  `allow-my-ip`, `block-ip`, `unblock-ip`, `--version`, `install --yes`;
- snapshots before every `apply` (last 10 kept) and one-command `rollback`;
- list sanity gate (>2× shrink or >5× growth is rejected; `RKN_ALLOW_LIST_SHRINK=1` bypass);
- conditional GET (`curl -z`) and set signatures: unchanged lists are not re-downloaded
  or re-loaded into `ipset`;
- logrotate config, `RandomizedDelaySec=1h`, systemd hardening, config backups,
  `0600` permissions;
- regression tests for every fixed bug; mock `iptables-restore`/`iptables-save`/`ipset-save`;
- documentation cleanup: duplicate `docs/*.md` removed, repository URLs fixed.

## v3.1.0 — 2026-08-09

### Fixed
- configuration edits no longer lose updates when several `config_tool.py` commands run at the same time: one lock now covers the full read-modify-write operation;
- legacy boolean configuration values are normalized safely, so a string such as `"false"` does not enable GeoIP;
- IPv6 addresses and networks are rejected before they can reach IPv4-only `ipset` sets and cause a failed apply;
- regenerated `SHA256SUMS`: it now covers every tracked release file and no longer references absent files.

### Documentation and validation
- updated release, installation, configuration, security, migration, troubleshooting, test, and publishing documentation for v3.1;
- added checksum validation to GitHub Actions and the publishing checklist;
- added mock tests for concurrent configuration writes, boolean normalization, and IPv6 rejection.

## v3.0.0

### Fixes
- fixed the bug where `setup_*` could clear already loaded `ipset` sets;
- switched `TSPUBLOCK` and `GOVIPS` updates to an atomic `temp set + swap` model;
- parallel list download failures no longer appear as successful updates;
- fixed the bug where update could return success even when list download failed;
- removed duplicate `INPUT -> GEOIP` rule accumulation;
- removed unsafe inline Python interpolation of user input;
- uninstall no longer removes global `/etc/ipset.conf` and `/etc/iptables/rules.v4` files.

### Architectural changes
- replaced `cron + daemon` with a single `systemd timer`;
- moved helper logic into `config_tool.py` and `geoip_apply.py`;
- added a dedicated interactive installer `installer.sh`;
- removed the `venv` dependency;
- rule restore after reboot is handled by a `systemd oneshot` service.

### Functional changes
- country-based GeoIP is now actually enforced through country CIDR sets;
- added allow/deny IP and allow/deny port rules;
- configuration files are updated with file locking and atomic writes;
- input values are validated with Python `ipaddress` and strict port checks.

### Limitations
- country-based GeoIP currently supports IPv4 only;
- country filtering relies on an external CIDR source (`ipdeny`).
