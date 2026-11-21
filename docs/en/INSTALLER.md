# Interactive installer

File:

```text
installer.sh
```

This is the recommended entry point for installing and removing RKN Watcher.

## What the installer does

### During installation

- checks that it is running as `root`;
- checks compatibility with `apt` / `dpkg`;
- validates required dependencies;
- installs missing packages;
- stores the list of packages installed specifically by this installer;
- **verifies nftables** (see below) and aborts the installation if the check fails;
- runs `rkn-watcher.sh install` (which also copies the `lib/` modules).

## nftables verification

Modern Debian/Ubuntu manage netfilter through `nftables`; `iptables` on top of it is a
wrapper (either over `nft` or over `legacy`). The installer checks four things:

| Check | Meaning | Reaction |
|---|---|---|
| the `nftables` package is installed | `dpkg-query` knows the package | installed automatically (`apt-get install -y nftables`) and recorded in the manifest |
| the `nft` binary is in `PATH` | rules can be read and verified | hard error, installation stops |
| `nft list ruleset` succeeds | kernel has `nf_tables` and we have `CAP_NET_ADMIN` | error with a hint (`modprobe nf_tables`, container without privileges) |
| the ruleset is not empty | rules are actually loaded | warning plus an offer to start `nftables.service` (when `/etc/nftables.conf` has rules) |

The installer also reports which backend `iptables` uses:

```text
[OK] iptables работает через nft-бэкенд (xtables-nft-multi)
[WARN] iptables работает через legacy-бэкенд (xtables-legacy-multi) — правила не попадут в nftables
```

An empty ruleset with `nftables.service` disabled is the usual cause of "rules were
applied but disappeared after reboot". In interactive mode the installer offers to enable
the service; with `install --yes` it only warns and never prompts.

Check it separately, without installing:

```bash
sudo ./installer.sh nft      # package + binary + ruleset + iptables backend
sudo ./installer.sh deps     # the "Netfilter" summary block
```

or menu entry "5) Check nftables".

### During removal

- performs full removal of all changes introduced by RKN Watcher;
- can perform emergency cleanup even if the main script is damaged or missing;
- can optionally remove packages that were previously installed by the installer itself.

## Run

```bash
sudo ./installer.sh
```

## Menu entries

1. Install / upgrade RKN Watcher
2. Check dependencies
3. Full removal of all managed changes
4. Show status
5. Check nftables
0. Exit

## Direct commands

```bash
sudo ./installer.sh install
sudo ./installer.sh uninstall
sudo ./installer.sh deps
sudo ./installer.sh status
sudo ./installer.sh nft
```

## Checked dependencies

- `iptables`
- `ipset`
- `nftables`
- `curl`
- `ca-certificates`
- `python3`
- `util-linux` (`flock`)

`ip6tables` ships with the `iptables` package on Debian/Ubuntu, so it is not installed
separately — IPv6 filtering activates automatically when it is present.

## What is removed during uninstall

- `systemd` units `rkn-watcher-update.timer`, `rkn-watcher-update.service`,
  `rkn-watcher-boot.service`;
- managed `iptables` **and** `ip6tables` chains (`TSPUBLOCK`, `GOVBLOCK`,
  `RKN_GEOIP_HOOK`, `RKN_DENY`, `GEOIP_DROP`, `RKN_PROTECT` and their `*6` counterparts);
- managed IPv4 and IPv6 `ipset` sets (`TSPUIPS`, `GOVIPS`, `GEOIP_ALLOW_IPS`,
  `GEOIP_DENY_IPS`, `GEOIP_COUNTRIES_ALLOW` and the `*6` variants);
- `/opt/rkn-watcher` (including `lib/`)
- `/etc/rkn-watcher`
- `/var/lib/rkn-watcher` (including `snapshots/` and `backups/`)
- `/var/log/rkn-watcher`
- `/usr/local/bin/rkn-watcher`

After that, the installer may offer to remove packages that it previously installed.
