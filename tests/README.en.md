# Tests

This folder contains a small set of safe mock tests that validate `iptables` / `ipset` logic without touching the real server firewall.

## What is covered

### Release metadata
- the version in `VERSION`, `rkn-watcher.sh`, README files, release notes, and changelogs stays consistent.

### For `rkn-watcher.sh`
- correct creation of `TSPUBLOCK` and `GOVIPS` rules;
- no duplicate hook rules in `INPUT`;
- successful `ipset` population on update;
- proper failure return on list download errors;
- preservation of the previous working `ipset` set after a failed update;
- cleanup of managed chains and sets via `remove_managed_firewall()`.

### For `geoip_apply.py`
- creation of `GEOIP_ALLOW_IPS`, `GEOIP_DENY_IPS`, and `GEOIP_COUNTRIES_ALLOW`;
- correct construction of `RKN_GEOIP_HOOK` and `GEOIP_DROP` chains;
- no duplicated `INPUT` hook on repeated apply;
- cleanup of hook and chains when `enabled=false`;
- treating a legacy `"false"` value as disabled rather than enabling GeoIP.

## Run

From the repository root:

```bash
chmod +x tests/run_tests.sh
./tests/run_tests.sh
```

## Requirements

- `bash`
- `python3`
- normal user execution is fine
- root is not required

## Note

These are not kernel-level firewall integration tests. They validate script logic through mock implementations of `iptables`, `ipset`, `curl`, and related commands.

## v3.2 regression coverage

| Regression | Scenario |
|---|---|
| fail-open booleans | `ENABLE_TSPUBLOCK="true"`/`"1"` keeps blocking enabled |
| fail-closed | invalid boolean is a hard error |
| masked `ipset` failure | failing `ipset restore` makes `update` return 1 |
| sanity gate | suspicious list shrink is rejected; `RKN_ALLOW_LIST_SHRINK=1` bypasses |
| deny independence | deny IP/ports work with any `FILTER_PORTS` |
| lockout protection | hook contains `-i lo` and `ESTABLISHED,RELATED` |
| `PORT_POLICY=strict` | only `FILTER_PORTS` are reachable |
| `--dry-run` | firewall state is untouched |
| readable errors | `FILTER_PORTS="443;80"` yields a config error, not a traceback |

The stand needs no root: `iptables`, `ip6tables`, `iptables-restore`, `iptables-save`,
`ipset`, `ipset save` and `curl` are mocked in Python.

## v3.2.1 regression coverage

| Regression | Scenario |
|---|---|
| modular assembly | the library is built from `lib/*.sh`; all functions must be present |
| IPv6 allow/deny | `2001:db8::/32` lands in `GEOIP_ALLOW_IPS6`, `2001:db8:dead::/48` in `GEOIP_DENY_IPS6`, both visible in `ip6tables` |
| malformed address | `2001:db8:::1` in an allow list is a config error, not a silent skip |
| IPv6 in `config_tool.py` | `add-ip 2001:db8::1` is accepted, `add-ip 2001:db8:::1` is rejected |
| netfilter backend | `NETFILTER_BACKEND=legacy` invokes `iptables-legacy`; `bogus` is a config error |
| snapshot rotation | a directory older than `SNAPSHOT_MAX_AGE_DAYS` is pruned, fresh ones and the last `SNAPSHOT_KEEP` survive |
| nftables in the installer | package/binary/empty ruleset/`iptables` backend are checked; missing `nftables` returns non-zero |

## Mocks

| Mock | Notes |
|---|---|
| `iptables` | state in `$STATE/iptables.json`, understands `-w N`, `-N/-F/-X/-A/-I/-C/-D/-L` |
| `ip6tables` | **separate** state `$STATE/iptables6.json`, so v4 and v6 rules never mix |
| `iptables-restore` / `iptables-save` | writes `iptables6.json` when invoked as `ip6tables-*`, supports `--noflush` |
| `ipset` | `create/add/destroy/swap/flush`, sets in `$STATE/ipset.json` |
| `curl` | controlled responses and error codes for list sources |

Run with a timeout (`timeout 150 bash tests/run_tests.sh`) so a hanging mock cannot stall
the pipeline.

## v3.2.1 result

```text
27 checks, All tests passed.
```
