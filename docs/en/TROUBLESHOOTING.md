# Troubleshooting

## Start with diagnostics

```bash
sudo rkn-watcher doctor
```

It checks:

- dependencies (`iptables`, `ipset`, `curl`, `python3`, `flock`) and `ip6tables`;
- kernel modules `ip_set`, `xt_set`, `xt_conntrack`, `xt_multiport`;
- the **netfilter backend**: configured `NETFILTER_BACKEND` vs. the one `iptables`
  actually uses, with a divergence warning;
- conflicts with `ufw` / `firewalld` / `docker`;
- boolean keys in `settings.conf` and duplicated keys;
- rule/config consistency (hook present when `ENABLE_*=y` and vice versa);
- list source reachability and timer state.

Only if that does not help, continue below.

## "Не найден каталог модулей lib/"

Since v3.2.1 the script consists of an entry point plus modules. If you upgraded by
copying files, `lib/` never reached `/opt/rkn-watcher`.

```bash
sudo install -d -m 0755 /opt/rkn-watcher/lib
sudo install -m 0755 lib/*.sh /opt/rkn-watcher/lib/
sudo rkn-watcher apply
```

Or reinstall with `sudo ./installer.sh install`, which copies the modules for you.

## Lost SSH access after enabling GeoIP

Rules do not break established sessions, but a new session from a non-allowed address
cannot be established. From the console/IPMI:

```bash
sudo rkn-watcher rollback        # roll back to the snapshot before the last apply
sudo rkn-watcher allow-my-ip     # allow the current IP
sudo rkn-watcher status
```

## Rules are applied but traffic is not filtered

Almost always a **netfilter backend mismatch**: rules were written via `iptables-nft`
while you inspect/filter through `iptables-legacy` (or the other way round).

```bash
sudo rkn-watcher doctor | grep -i backend
# netfilter backend: auto (фактически: legacy, утилита: iptables-legacy)
```

If both backends exist, set the intended one explicitly:

```bash
echo 'NETFILTER_BACKEND="nft"' | sudo tee -a /etc/rkn-watcher/settings.conf
sudo rkn-watcher apply
```

Check your chains with the same tool:

```bash
sudo iptables-nft -L RKN_GEOIP_HOOK -v -n     # or iptables-legacy
```

## IPv6 rules are not created

```bash
command -v ip6tables && sudo ip6tables -L INPUT -v -n
```

Reasons:

- `ip6tables` is not installed (it usually comes with the `iptables` package) — the IPv6
  part is skipped with a warning and `doctor` prints
  `ip6tables: нет (IPv6 не защищён)`;
- there are no IPv6 entries and `PORT_POLICY=geoip_only` — the IPv6 hook is not needed
  and is not created (normal, not an error).

## An IPv6 address is rejected

This used to be expected (v3.1 supported IPv4 only); since v3.2.1 it is not. If the
error persists, validate the entry:

```bash
python3 -c 'import ipaddress,sys; ipaddress.ip_network(sys.argv[1], strict=False)' 2001:db8::/32
```

Entries like `2001:db8:::1` or `2001:db8::/129` are configuration errors, not silent
skips.

## "Update completed with errors"

Details are in `update.log`. Typical causes:

- the source is unreachable — the old set keeps working, retry later;
- `sanity check failed` — the list changed 2x or more; verify the source and, if the
  change is expected, run `sudo RKN_ALLOW_LIST_SHRINK=1 rkn-watcher update`;
- `ipset restore failed` — check free space and `maxelem`, the old set is preserved.

## "Invalid boolean value" and rules are not applied

Check `settings.conf`: only `y/n`, `yes/no`, `true/false`, `1/0`, `on/off` are allowed.
Any other value blocks application (fail-closed).

If a key appears several times, the last value wins — `doctor` lists such keys:

```bash
sudo rkn-watcher doctor | grep -i дублир
```

## Installer: "nft cannot read the ruleset" or "ruleset is empty"

The installer verifies nftables before installing. Messages and fixes:

```bash
sudo nft list ruleset            # if this works, permissions/kernel are fine
modprobe nf_tables
uname -r                         # a very old kernel without nf_tables — upgrade it
```

- **"nft binary not found"** — `apt-get install -y nftables` (the installer does it in
  interactive mode);
- **"nft cannot read the ruleset"** — usually a container without `CAP_NET_ADMIN`
  (`--privileged` or explicit capability) or a kernel without `nf_tables`;
- **"ruleset is empty"** — no rules loaded; if `/etc/nftables.conf` has rules, then
  `nftables.service` is not running:

  ```bash
  sudo systemctl enable --now nftables.service
  sudo nft list ruleset
  ```

Standalone check without installing: `sudo ./installer.sh nft` (or menu entry 5).

## nftables rules disappeared after reboot

Rules loaded by hand are not persisted. Enable the service:

```bash
sudo systemctl enable nftables.service
systemctl is-enabled nftables.service
```

RKN Watcher's own rules are restored by the separate `rkn-watcher-boot.service` unit
(iptables/ipset) and do not depend on nftables.

## The installer says it is not running as root

```bash
sudo ./installer.sh
```

## Helper files not found

Cause: `rkn-watcher.sh` runs without `config_tool.py`, `geoip_apply.py` and `lib/`.

Fix: use `git clone`, or put `installer.sh`, `rkn-watcher.sh`, `lib/`,
`config_tool.py`, `geoip_apply.py` into one directory.

## TSPUBLOCK / GOVIPS lists are not downloading

```bash
curl -I https://github.com/
curl -I https://raw.githubusercontent.com/
sudo tail -n 100 /var/log/rkn-watcher/update.log
```

On download failure the previous working `ipset` is preserved.

## Country GeoIP does not apply the country list

```bash
sudo cat /etc/rkn-watcher/whitelist.json
sudo ipset list GEOIP_COUNTRIES_ALLOW | head -20
sudo ipset list GEOIP_COUNTRIES_ALLOW6 | head -20
```

If the set is empty:

- check access to `ipdeny.com`;
- check the country code (`FI`, `DE`, `JP` — ISO alpha-2, upper case);
- read `/var/log/rkn-watcher/geoip.log` for the reason (`countries=…`).

## Rules did not change after a config edit

```bash
sudo rkn-watcher apply
```

## The timer does not run

```bash
systemctl status rkn-watcher-update.timer
systemctl status rkn-watcher-update.service
systemctl list-timers | grep rkn-watcher
```

If the timer is disabled:

```bash
sudo systemctl enable --now rkn-watcher-update.timer
```

## GeoIP is enabled and access is cut too broadly

Likely cause: `enabled=true`, `countries` populated, and your IP or country is not in
the allow set.

Fix:

- temporarily allow your IP (`rkn-watcher allow-my-ip`);
- or disable GeoIP;
- then adjust the country list.

## Snapshots take too much space

```bash
sudo rkn-watcher snapshots
```

Retention is bounded: the last `SNAPSHOT_KEEP` (10) plus everything younger than
`SNAPSHOT_MAX_AGE_DAYS` (30 days). To shrink:

```ini
SNAPSHOT_KEEP="5"
SNAPSHOT_MAX_AGE_DAYS="14"
```

Rotation happens when the next snapshot is created (`apply`/`update`/`snapshot`).

## Quickly disable GeoIP only

```bash
sudo /opt/rkn-watcher/config_tool.py set-enabled false
sudo rkn-watcher apply
```
