#!/usr/bin/env bash
# Сборка релиза: проверки, манифест контрольных сумм, архив.
#
#   ./release.sh            # проверить, пересобрать SHA256SUMS и собрать архив
#   ./release.sh --check    # только проверить существующий SHA256SUMS (используется в CI)
#   ./release.sh --sign     # дополнительно подписать манифест GPG-ключом
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

ROOT="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
cd "$ROOT"

MANIFEST="SHA256SUMS"
# В манифест попадают только артефакты релиза: манифест и подпись сами себя не покрывают.
RELEASE_FILES=(
    installer.sh
    release.sh
    rkn-watcher.sh
    lib/config.sh
    lib/common.sh
    lib/firewall.sh
    lib/snapshots.sh
    lib/lists.sh
    lib/services.sh
    lib/ui.sh
    lib/cli.sh
    config_tool.py
    geoip_apply.py
    VERSION
    LICENSE
    README.md
    README.ru.md
    README.en.md
    CHANGELOG.md
    CHANGELOG.ru.md
    CHANGELOG.en.md
    RELEASE_NOTES.md
    RELEASE_NOTES.ru.md
    RELEASE_NOTES.en.md
    PUBLISHING.md
    PUBLISHING.ru.md
    PUBLISHING.en.md
    docs/README.md
    docs/ru/INSTALL.md
    docs/ru/INSTALLER.md
    docs/ru/USAGE.md
    docs/ru/CONFIGURATION.md
    docs/ru/MIGRATION.md
    docs/ru/TROUBLESHOOTING.md
    docs/ru/SECURITY.md
    docs/en/INSTALL.md
    docs/en/INSTALLER.md
    docs/en/USAGE.md
    docs/en/CONFIGURATION.md
    docs/en/MIGRATION.md
    docs/en/TROUBLESHOOTING.md
    docs/en/SECURITY.md
    tests/README.md
    tests/README.ru.md
    tests/README.en.md
    tests/run_tests.sh
    .github/workflows/tests.yml
)

info() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERR] %s\n' "$*" >&2; exit 1; }

check_manifest() {
    [[ -f "$MANIFEST" ]] || die "$MANIFEST отсутствует — запустите ./release.sh без --check"
    info "Проверка контрольных сумм ($(wc -l < "$MANIFEST") файлов)"
    if ! sha256sum -c --quiet "$MANIFEST"; then
        die "Контрольные суммы не совпадают. Пересоберите манифест: ./release.sh"
    fi
    info "Контрольные суммы в порядке"
}

check_version_consistency() {
    local version
    version=$(tr -d '\r\n' < VERSION)
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION имеет неверный формат: $version"
    grep -Fq "VERSION=\"$version\"" lib/config.sh || die "VERSION=$version не совпадает с lib/config.sh"
    local f
    for f in README.md README.ru.md README.en.md; do
        grep -Fq "# RKN Watcher v$version" "$f" || die "$f не содержит версию v$version"
    done
    grep -Fq "v$version" CHANGELOG.ru.md || die "CHANGELOG.ru.md не содержит v$version"
    grep -Fq "v$version" CHANGELOG.en.md || die "CHANGELOG.en.md не содержит v$version"
    info "Версия $version согласована во всех файлах"
}

rebuild_manifest() {
    local missing=0
    local f
    for f in "${RELEASE_FILES[@]}"; do
        [[ -f "$f" ]] || { printf '[WARN] нет файла %s\n' "$f" >&2; missing=1; }
    done
    if (( missing )); then
        die "Не все файлы релиза на месте"
    fi
    sha256sum "${RELEASE_FILES[@]}" > "$MANIFEST"
    info "Манифест пересобран: $MANIFEST ($(wc -l < "$MANIFEST") файлов)"
}

normalize_modes() {
    # Права в архиве не должны зависеть от того, как файлы получены (git без exec-bit,
    # распаковка zip, копирование). Скрипты всегда 0755, остальное 0644.
    local f
    for f in "${RELEASE_FILES[@]}"; do
        [[ -f "$f" ]] || continue
        case "$f" in
            *.sh) chmod 0755 "$f" ;;
            *) chmod 0644 "$f" ;;
        esac
    done
}

build_archive() {
    local version archive
    version=$(tr -d '\r\n' < VERSION)
    archive="rkn-watcher-${version}.tar.gz"
    local files=()
    local f
    for f in "${RELEASE_FILES[@]}"; do
        files+=("$f")
    done
    files+=("$MANIFEST")
    normalize_modes
    # --owner/--group 0: в архиве не должно быть локальных uid/gid
    tar --owner=0 --group=0 --numeric-owner -czf "$archive" "${files[@]}"
    info "Архив: $archive ($(du -h "$archive" | cut -f1))"

    # zip для GitHub Release: собирается тем же списком через python (не нужен пакет zip)
    local zipfile="rkn-watcher-${version}.zip"
    rm -f "$zipfile"
    python3 - "$zipfile" "${files[@]}" <<'PY'
import sys
import zipfile
from pathlib import Path

archive = sys.argv[1]
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as zf:
    for name in sys.argv[2:]:
        path = Path(name)
        if path.is_dir():
            for f in sorted(path.rglob('*')):
                if f.is_file():
                    zf.write(f, f.as_posix())
        elif path.exists():
            zf.write(path, path.as_posix())
PY
    if [[ -f "$zipfile" ]]; then
        info "Архив: $zipfile ($(du -h "$zipfile" | cut -f1))"
    fi

    # контрольные суммы самих артефактов — для приложения к GitHub Release
    sha256sum "$archive" > "${archive}.sha256"
    [[ -f "$zipfile" ]] && sha256sum "$zipfile" > "${zipfile}.sha256"
    info "Контрольные суммы артефактов: ${archive}.sha256${zipfile:+ ${zipfile}.sha256}"
    if command -v gpg >/dev/null 2>&1 && [[ "${1:-}" == "--sign" ]]; then
        gpg --detach-sign --armor "$MANIFEST"
        gpg --detach-sign --armor "$archive"
        info "Подписи: $MANIFEST.asc, $archive.asc"
    fi
}

main() {
    case "${1:-}" in
        --check)
            check_manifest
            ;;
        --sign)
            check_version_consistency
            rebuild_manifest
            check_manifest
            build_archive --sign
            ;;
        *)
            check_version_consistency
            normalize_modes
            rebuild_manifest
            check_manifest
            build_archive
            ;;
    esac
}

main "$@"
