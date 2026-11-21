# Publishing the release

## 1. Validate before publishing

From the release directory root:

```bash
bash -n installer.sh rkn-watcher.sh lib/*.sh tests/run_tests.sh release.sh
shellcheck -S warning --shell=bash installer.sh rkn-watcher.sh lib/*.sh release.sh tests/run_tests.sh
python3 -m py_compile config_tool.py geoip_apply.py
python3 -m pyflakes config_tool.py geoip_apply.py
timeout 150 bash tests/run_tests.sh
./release.sh --check
```

Expected result:

- no Bash syntax errors (all 8 `lib/` modules included);
- `shellcheck -S warning` is clean;
- `py_compile` / `pyflakes` are clean;
- `All tests passed.` (27 checks);
- every entry in `SHA256SUMS` reports `OK`.

`./release.sh` performs the same checks plus version validation, manifest rebuild and
archive creation.

## 2. Version and tag

The version lives in two places and must match:

- `VERSION`;
- `VERSION="..."` in `lib/config.sh`.

`release.sh` verifies this and refuses to build on a mismatch. Tag:

```bash
git tag -a v3.2.1 -m "RKN Watcher v3.2.1"
git push origin v3.2.1
```

## 3. What to attach to the GitHub Release

Use `RELEASE_NOTES.en.md` or `RELEASE_NOTES.ru.md` as the description.
`./release.sh` produces:

| File | What it is |
|---|---|
| `rkn-watcher-3.2.1.tar.gz` | full release source (including `.github/workflows`, `docs/`, `tests/`) |
| `rkn-watcher-3.2.1.zip` | the same as a zip, for Windows/web downloads |
| `SHA256SUMS` | checksums of all 47 release files (verified inside the archives) |
| `rkn-watcher-3.2.1.tar.gz.sha256`, `rkn-watcher-3.2.1.zip.sha256` | checksums of the archives themselves |

Both archives contain `SHA256SUMS`, so verification works right after unpacking:

```bash
tar xzf rkn-watcher-3.2.1.tar.gz -C rkn-watcher-3.2.1 --one-top-level
cd rkn-watcher-3.2.1 && sha256sum -c SHA256SUMS
```

Modes are normalized inside the archives (`*.sh` → `0755`, everything else `0644`) and
the owner is `0/0`, so unpacking as any user yields a working file set.

## 4. What should not be committed

Do not commit runtime data from a real server:

- `/etc/rkn-watcher/*`
- `/var/log/rkn-watcher/*`
- `/var/lib/rkn-watcher/*` (including `snapshots/`, `backups/`, `state/`)
- systemd unit files copied from an installed machine
- real `iptables` / `ip6tables` / `ipset` dumps

## 5. Release automation

```bash
./release.sh            # check versions, rebuild SHA256SUMS, build the archive
./release.sh --check    # verify the existing manifest (used by CI)
./release.sh --sign     # additionally GPG-sign the manifest and archive
```

The manifest covers 47 files: the entry point, every `lib/*.sh` module, the Python
helpers, `VERSION`, `LICENSE`, README/CHANGELOG/RELEASE_NOTES/PUBLISHING (ru/en/md),
`docs/**`, `tests/**` and the CI workflow. A new release file means a new line in
`RELEASE_FILES` inside `release.sh`.

CI (`.github/workflows/tests.yml`) runs `bash -n`, `shellcheck -S warning`,
`py_compile`, `pyflakes`, the mock test suite and `./release.sh --check`, so a release
cannot ship with a stale manifest or version.

## 6. Documentation checklist for a release

- version in `README*.md`, `CHANGELOG*`, `RELEASE_NOTES*`, `docs/README.md`;
- new `settings.conf` keys documented in `docs/{ru,en}/CONFIGURATION.md`;
- new commands documented in `docs/{ru,en}/USAGE.md`;
- new functionality listed in `CHANGELOG.{ru,en}.md` and `RELEASE_NOTES.{ru,en}.md`;
- Russian docs edited first, then mirrored to English.
