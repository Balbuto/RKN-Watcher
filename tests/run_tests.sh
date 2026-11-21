#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

extract_bash_lib() {
    # Монолитный скрипт + модули lib/*.sh собираются в один sourcing-файл,
    # чтобы тесты проверяли ровно тот код, который уходит в установку.
    mkdir -p "$TMP_ROOT/lib"
    python3 - "$REPO_ROOT" "$TMP_ROOT/rkn-lib.sh" "$TMP_ROOT/lib" <<'PY'
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
target = Path(sys.argv[2])
lib_out = Path(sys.argv[3])

src = (repo / 'rkn-watcher.sh').read_text()
marker = '\nmain "$@"\n'
idx = src.rfind(marker)
if idx == -1:
    raise SystemExit('failed to locate main invocation')
head = src[:idx]

# вырезаем динамическую загрузку модулей из установленного каталога
head = re.sub(r'^resolve_lib_dir\(\) \{.*?^\}\n', '', head, flags=re.M | re.S)
head = re.sub(r'^load_lib\(\) \{.*?^\}\n', '', head, flags=re.M | re.S)
head = re.sub(r'^load_lib$\n', '', head, flags=re.M)
head = re.sub(r'^resolve_sources$\n', '', head, flags=re.M)

head = re.sub(r'^source "\$RKN_ROOT/lib/config.sh"\n', '', head, flags=re.M)
head = re.sub(r'^rkn_load_modules$\n', '', head, flags=re.M)
head = re.sub(r'^RKN_ROOT=.*?\n', '', head, flags=re.M)
head = re.sub(r'^if \[\[ ! -f "\$RKN_ROOT/lib/config\.sh".*?^fi\n', '', head, flags=re.M | re.S)

modules = []
for name in ('config', 'common', 'firewall', 'snapshots', 'lists', 'services', 'ui', 'cli'):
    path = repo / 'lib' / f'{name}.sh'
    text = path.read_text()
    (lib_out / f'{name}.sh').write_text(text)
    if name == 'config':
        # в тестах модули уже подгружены явно — динамическую загрузку не тащим
        text = re.sub(r'^LIB_DIR=.*?^\}\n', '', text, flags=re.M | re.S)
    modules.append(text)

# тесты собирают «библиотеку»: константы + модули, без вызова main()
body = head + '\n' + '\n'.join(modules) + '\n'
body = re.sub(r'^main "\$@"\n', '', body, flags=re.M)
body = re.sub(r'^rkn_load_modules\n', '', body, flags=re.M)
body = re.sub(r'^resolve_sources\n', '', body, flags=re.M)
target.write_text(body)
PY
}

create_fake_iptables() {
    cat > "$1" <<'PY'
#!/usr/bin/env python3
import json, os, sys
state_file = os.path.join(os.environ['STATE'], 'iptables.json')
os.makedirs(os.path.dirname(state_file), exist_ok=True)
if os.path.exists(state_file):
    with open(state_file) as f:
        st = json.load(f)
else:
    st = {'chains': {'INPUT': []}}
st['chains'].setdefault('INPUT', [])
args = sys.argv[1:]
# iptables -w 5 ... : ожидание xtables lock не влияет на семантику, отбрасываем
if len(args) >= 2 and args[0] == '-w':
    args = args[2:]
rc = 0
out = ''
def save():
    with open(state_file, 'w') as f:
        json.dump(st, f)
def rule(parts):
    return ' '.join(parts)
if args[0] == '-N':
    st['chains'].setdefault(args[1], [])
elif args[0] == '-F':
    st['chains'].setdefault(args[1], [])
    st['chains'][args[1]] = []
elif args[0] == '-X':
    ch = args[1]
    if st['chains'].get(ch):
        rc = 1
    else:
        st['chains'].pop(ch, None)
elif args[0] in ('-A', '-I'):
    ch = args[1]
    st['chains'].setdefault(ch, [])
    rest = args[2:]
    if args[0] == '-I' and rest and rest[0].isdigit():
        pos = int(rest[0])
        rest = rest[1:]
        st['chains'][ch].insert(max(pos - 1, 0), rule(rest))
    elif args[0] == '-I':
        st['chains'][ch].insert(0, rule(rest))
    else:
        st['chains'][ch].append(rule(rest))
elif args[0] in ('-C', '-D'):
    ch = args[1]
    rest = rule(args[2:])
    rules = st['chains'].setdefault(ch, [])
    if rest in rules:
        if args[0] == '-D':
            rules.remove(rest)
    else:
        rc = 1
elif args[0] == '-L':
    ch = args[1]
    if ch not in st['chains']:
        rc = 1
    else:
        out = '\n'.join(st['chains'][ch])
save()
if out:
    print(out)
sys.exit(rc)
PY
    chmod +x "$1"
}

create_fake_ipset() {
    cat > "$1" <<'PY'
#!/usr/bin/env python3
import json, os, sys
state_file = os.path.join(os.environ['STATE'], 'ipset.json')
os.makedirs(os.path.dirname(state_file), exist_ok=True)
if os.path.exists(state_file):
    with open(state_file) as f:
        st = json.load(f)
else:
    st = {}
args = sys.argv[1:]
rc = 0
out = ''
if args and args[0] == '-exist':
    args = args[1:]
def save():
    with open(state_file, 'w') as f:
        json.dump(st, f)
if args[0] == 'create':
    st.setdefault(args[1], [])
elif args[0] == 'list':
    if len(args) == 1:
        out = '\n'.join(st)
    else:
        name = args[1]
        if name not in st:
            rc = 1
        else:
            out = f'Name: {name}\nNumber of entries: {len(st[name])}\n'
elif args[0] == 'add':
    st.setdefault(args[1], [])
    if args[2] not in st[args[1]]:
        st[args[1]].append(args[2])
elif args[0] == 'save':
    if len(args) == 1:
        for name, vals in st.items():
            print(f'create {name} hash:net family inet maxelem 1000')
            for v in vals:
                print(f'add {name} {v}')
        sys.exit(0)
    name = args[1]
    if name in st:
        print(f'create {name} hash:net family inet maxelem 1000')
        for v in st[name]:
            print(f'add {name} {v}')
    sys.exit(0)
elif args[0] == 'restore':
    if os.environ.get('MOCK_IPSET_RESTORE_FAIL') == '1':
        sys.stdin.read()
        sys.exit(1)
    for line in sys.stdin.read().splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == 'create':
            st.setdefault(parts[1], [])
        elif parts[0] == 'flush':
            st[parts[1]] = []
        elif parts[0] == 'add':
            st.setdefault(parts[1], [])
            if parts[2] not in st[parts[1]]:
                st[parts[1]].append(parts[2])
elif args[0] == 'swap':
    st.setdefault(args[1], [])
    st.setdefault(args[2], [])
    st[args[1]], st[args[2]] = st[args[2]], st[args[1]]
elif args[0] == 'destroy':
    st.pop(args[1], None)
save()
if out:
    print(out, end='')
sys.exit(rc)
PY
    chmod +x "$1"
}

create_fake_curl() {
    cat > "$1" <<'PY'
#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
out = None
url = None
i = 0
opts_with_value = {'-o', '--output', '--connect-timeout', '--max-time', '--retry', '--retry-delay'}
while i < len(args):
    if args[i] in opts_with_value:
        if args[i] in {'-o', '--output'}:
            out = args[i + 1]
        i += 2
    elif args[i].startswith('-'):
        i += 1
    else:
        url = args[i]
        i += 1
if os.environ.get('MOCK_CURL_FAIL') == '1':
    sys.exit(22)
content = ''
if url and 'skipa_cidr.txt' in url:
    content = '1.1.1.0/24\n2.2.2.0/24\n'
elif url and 'blacklist-v4.ipset' in url:
    content = 'add blacklist-v4 3.3.3.0/24\nadd blacklist-v4 4.4.4.0/24\n'
if out:
    with open(out, 'w') as f:
        f.write(content)
sys.exit(0)
PY
    chmod +x "$1"
}

create_fake_iptables_restore() {
    cat > "$1" <<'PY'
#!/usr/bin/env python3
"""Минимальный mock iptables-restore: понимает формат *filter/:CHAIN/-F/-A/COMMIT."""
import json, os, sys
name = os.path.basename(sys.argv[0])
state_file = os.path.join(os.environ['STATE'], 'iptables6.json' if 'ip6tables' in name else 'iptables.json')
os.makedirs(os.path.dirname(state_file), exist_ok=True)
if os.path.exists(state_file):
    with open(state_file) as f:
        st = json.load(f)
else:
    st = {'chains': {'INPUT': []}}
st['chains'].setdefault('INPUT', [])
if os.environ.get('MOCK_IPTABLES_RESTORE_FAIL') == '1':
    sys.stdin.read()
    sys.exit(1)
for line in sys.stdin.read().splitlines():
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    if line.startswith('*') or line == 'COMMIT':
        continue
    parts = line.split()
    if parts[0].startswith(':'):
        st['chains'].setdefault(parts[0][1:], [])
    elif parts[0] == '-F':
        st['chains'][parts[1]] = []
    elif parts[0] == '-A':
        st['chains'].setdefault(parts[1], []).append(' '.join(parts[2:]))
    else:
        pass
with open(state_file, 'w') as f:
    json.dump(st, f)
sys.exit(0)
PY
    chmod +x "$1"
    if [[ ! -e "$(dirname "$1")/ip6tables-restore" ]]; then
        ln -s "$1" "$(dirname "$1")/ip6tables-restore"
    fi
}

create_fake_iptables_save() {
    cat > "$1" <<'PY'
#!/usr/bin/env python3
import json, os, sys
name = os.path.basename(sys.argv[0])
state_file = os.path.join(os.environ['STATE'], 'iptables6.json' if 'ip6tables' in name else 'iptables.json')
if not os.path.exists(state_file):
    sys.exit(1)
st = json.load(open(state_file))
print('*filter')
print(':INPUT ACCEPT [0:0]')
for chain, rules in st['chains'].items():
    if chain != 'INPUT':
        print(f':{chain} - [0:0]')
for rule in st['chains'].get('INPUT', []):
    print(f'-A INPUT {rule}')
for chain, rules in st['chains'].items():
    if chain == 'INPUT':
        continue
    for rule in rules:
        print(f'-A {chain} {rule}')
print('COMMIT')
PY
    chmod +x "$1"
    if [[ ! -e "$(dirname "$1")/ip6tables-save" ]]; then
        ln -s "$1" "$(dirname "$1")/ip6tables-save"
    fi
}

create_fake_ipset_save() {
    cat > "$1" <<'PY'
#!/usr/bin/env python3
import json, os, sys
state_file = os.path.join(os.environ['STATE'], 'ipset.json')
if not os.path.exists(state_file):
    sys.exit(1)
st = json.load(open(state_file))
for name, vals in st.items():
    print(f'create {name} hash:net family inet maxelem 1000 -exist')
    for v in vals:
        print(f'add {name} {v}')
PY
    chmod +x "$1"
}

create_fake_ip6tables_iptables() {
    # ip6tables должен писать в отдельное состояние, иначе v4- и v6-правила
    # смешиваются и тесты «зеленеют» на неверной модели
    cat > "$(dirname "$1")/ip6tables" <<'PY'
#!/usr/bin/env python3
import json, os, sys
state_file = os.path.join(os.environ['STATE'], 'iptables6.json')
os.makedirs(os.path.dirname(state_file), exist_ok=True)
if os.path.exists(state_file):
    with open(state_file) as f:
        st = json.load(f)
else:
    st = {'chains': {'INPUT': []}}
st['chains'].setdefault('INPUT', [])
args = sys.argv[1:]
if len(args) >= 2 and args[0] == '-w':
    args = args[2:]
rc = 0
out = ''
def save():
    with open(state_file, 'w') as f:
        json.dump(st, f)
def rule(parts):
    return ' '.join(parts)
if args[0] == '-N':
    st['chains'].setdefault(args[1], [])
elif args[0] == '-F':
    st['chains'].setdefault(args[1], [])
    st['chains'][args[1]] = []
elif args[0] == '-X':
    if st['chains'].get(args[1]):
        rc = 1
    else:
        st['chains'].pop(args[1], None)
elif args[0] in ('-A', '-I'):
    ch = args[1]
    st['chains'].setdefault(ch, [])
    rest = args[2:]
    if args[0] == '-I' and rest and rest[0].isdigit():
        pos = int(rest[0])
        rest = rest[1:]
        st['chains'][ch].insert(max(pos - 1, 0), rule(rest))
    elif args[0] == '-I':
        st['chains'][ch].insert(0, rule(rest))
    else:
        st['chains'][ch].append(rule(rest))
elif args[0] in ('-C', '-D'):
    ch = args[1]
    rest = rule(args[2:])
    rules = st['chains'].setdefault(ch, [])
    if rest in rules:
        if args[0] == '-D':
            rules.remove(rest)
    else:
        rc = 1
elif args[0] == '-L':
    if args[1] not in st['chains']:
        rc = 1
    else:
        out = '\n'.join(st['chains'][args[1]])
save()
if out:
    print(out)
sys.exit(rc)
PY
    chmod +x "$(dirname "$1")/ip6tables"
}

create_fake_netfilter_persistent() {
    cat > "$1" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$1"
}

run_bash_logic_tests() {
    # Переменные ниже переопределяют значения из sourced-библиотеки (rkn-lib.sh),
    # поэтому shellcheck не видит их использования внутри функций библиотеки.
    # shellcheck disable=SC2034
    {
    local root="$TMP_ROOT/bash"
    local bin="$root/bin"
    export STATE="$root/state"
    mkdir -p "$bin" "$STATE" "$root/logs" "$root/install" "$root/etc" "$root/data/statefiles" "$root/data/locks"

    create_fake_iptables "$bin/iptables"
    create_fake_ip6tables_iptables "$bin/iptables"
    create_fake_iptables_restore "$bin/iptables-restore"
    create_fake_iptables_save "$bin/iptables-save"
    create_fake_ipset "$bin/ipset"
    create_fake_ipset_save "$bin/ipset-save"
    create_fake_curl "$bin/curl"
    create_fake_netfilter_persistent "$bin/netfilter-persistent"
    export PATH="$bin:$PATH"

    # shellcheck disable=SC1090,SC2034
    source "$TMP_ROOT/rkn-lib.sh"

    INSTALL_DIR="$root/install"
    CONFIG_DIR="$root/etc"
    DATA_DIR="$root/data"
    CACHE_DIR="$DATA_DIR/cache"
    COUNTRY_CACHE_DIR="$CACHE_DIR/countries"
    STATE_DIR="$DATA_DIR/statefiles"
    LIST_CACHE_DIR="$DATA_DIR/lists"
    SNAPSHOT_DIR="$DATA_DIR/snapshots"
    mkdir -p "$LIST_CACHE_DIR" "$SNAPSHOT_DIR"
    LOCK_DIR="$DATA_DIR/locks"
    LOG_DIR="$root/logs"
    SETTINGS_FILE="$CONFIG_DIR/settings.conf"
    WHITELIST_FILE="$CONFIG_DIR/whitelist.json"
    BLACKLIST_FILE="$CONFIG_DIR/blacklist.json"
    IPSET_STATE_FILE="$STATE_DIR/ipset.conf"
    UPDATE_LOCK_FILE="$LOCK_DIR/update.lock"
    SETTINGS_LOCK_FILE="$LOCK_DIR/settings.lock"
    UPDATE_LOG="$LOG_DIR/update.log"
    ACTION_LOG="$LOG_DIR/actions.log"
    GEOIP_LOG="$LOG_DIR/geoip.log"

    }

    cat > "$SETTINGS_FILE" <<'EOF2'
FILTER_PORTS="all"
LOG_RST="n"
AUTO_UPDATE="y"
ENABLE_TSPUBLOCK="y"
ENABLE_GOVIPS="y"
EOF2

    setup_tspublock_rules
    setup_tspublock_rules
    setup_govips_rules
    setup_govips_rules
    python3 - "$STATE" <<'PY'
import json, os, sys
state_dir = sys.argv[1]
state = json.load(open(os.path.join(state_dir, 'iptables.json')))
input_rules = state['chains']['INPUT']
assert input_rules.count('-j TSPUBLOCK') == 1, input_rules
assert input_rules.count('-j GOVBLOCK') == 1, input_rules
assert state['chains']['TSPUBLOCK'] == ['-p tcp --tcp-flags RST RST -m set --match-set TSPUIPS src -j DROP']
assert state['chains']['GOVBLOCK'] == ['-p tcp --tcp-flags RST RST -m set --match-set GOVIPS src -j DROP']
# IPv6-цепочки не должны лезть в INPUT, если ip6tables = iptables-mock тот же файл
print('OK: setup rules do not duplicate INPUT hooks')
PY

    update_tspublock_list >/dev/null
    update_govips_list >/dev/null
    python3 - <<'PY'
import json, os
state = json.load(open(os.path.join(os.environ['STATE'], 'ipset.json')))
assert sorted(state['TSPUIPS']) == ['1.1.1.0/24', '2.2.2.0/24']
assert sorted(state['GOVIPS']) == ['3.3.3.0/24', '4.4.4.0/24']
print('OK: successful updates populate ipset sets')
PY

    python3 - <<'PY'
import json, os
path = os.path.join(os.environ['STATE'], 'ipset.json')
state = json.load(open(path))
state['TSPUIPS'] = ['9.9.9.0/24']
json.dump(state, open(path, 'w'))
PY
    export MOCK_CURL_FAIL=1
    if update_tspublock_list >/dev/null 2>&1; then
        echo 'FAIL: update_tspublock_list returned success on download error' >&2
        return 1
    fi
    unset MOCK_CURL_FAIL
    python3 - <<'PY'
import json, os
state = json.load(open(os.path.join(os.environ['STATE'], 'ipset.json')))
assert state['TSPUIPS'] == ['9.9.9.0/24']
print('OK: failed update returns error and preserves old set')
PY

    # --- регрессия: legacy-значения boolean не должны выключать блокировку ---
    printf 'FILTER_PORTS="all"\nLOG_RST="n"\nAUTO_UPDATE="y"\nENABLE_TSPUBLOCK="true"\nENABLE_GOVIPS="1"\n' > "$SETTINGS_FILE"
    rm -f "$STATE/iptables.json"
    setup_tspublock_rules
    setup_govips_rules
    # --- регрессия: резкое уменьшение списка не применяется ---
    printf '100\n' > "$STATE_DIR/tspu_count.txt"
    cat > "$LIST_CACHE_DIR/tspu.raw" <<'RAW'
1.1.1.0/24
RAW
    if update_tspublock_list >/dev/null 2>&1; then
        echo 'FAIL: suspicious list shrink was applied without sanity check' >&2
        return 1
    fi
    echo 'OK: sanity check blocks suspicious list shrink'
    RKN_ALLOW_LIST_SHRINK=1 update_tspublock_list >/dev/null || { echo 'FAIL: RKN_ALLOW_LIST_SHRINK=1 did not bypass sanity check' >&2; return 1; }
    unset RKN_ALLOW_LIST_SHRINK || true
    echo 'OK: RKN_ALLOW_LIST_SHRINK=1 allows intentional shrink'

    python3 - "$STATE" <<'PY'
import json, os, sys
state = json.load(open(os.path.join(sys.argv[1], 'iptables.json')))
hook = state['chains']['INPUT']
assert '-j TSPUBLOCK' in hook, hook
assert '-j GOVBLOCK' in hook, hook
print('OK: legacy boolean values (true/1) in settings.conf keep blocking enabled')
PY

    # --- регрессия: некорректное boolean-значение должно быть явной ошибкой ---
    printf 'ENABLE_TSPUBLOCK="yes please"\n' > "$SETTINGS_FILE"
    if setup_tspublock_rules 2>/dev/null; then
        echo 'FAIL: invalid boolean value was silently accepted' >&2
        return 1
    fi
    echo 'OK: invalid boolean value in settings.conf is a hard error'
    printf 'FILTER_PORTS="all"\nLOG_RST="n"\nAUTO_UPDATE="y"\nENABLE_TSPUBLOCK="y"\nENABLE_GOVIPS="y"\n' > "$SETTINGS_FILE"

    # --- netfilter backend: явный выбор и валидация значения ---
    cat > "$bin/iptables-legacy" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "LEGACY-CALLED $*" >> "$STATE/legacy.log"
exec "$(dirname "$0")/iptables" "$@"
SH
    chmod +x "$bin/iptables-legacy"
    set_setting NETFILTER_BACKEND legacy >/dev/null
    # shellcheck disable=SC2034
    NETFILTER_BACKEND_CACHE=""
    : > "$STATE/legacy.log"
    setup_tspublock_rules >/dev/null
    grep -q "LEGACY-CALLED" "$STATE/legacy.log" || { echo 'FAIL: NETFILTER_BACKEND=legacy did not switch tool' >&2; return 1; }
    set_setting NETFILTER_BACKEND bogus >/dev/null
    # shellcheck disable=SC2034
    NETFILTER_BACKEND_CACHE=""
    if netfilter_backend >/dev/null 2>&1; then
        echo 'FAIL: invalid NETFILTER_BACKEND accepted' >&2
        return 1
    fi
    set_setting NETFILTER_BACKEND auto >/dev/null
    # shellcheck disable=SC2034
    NETFILTER_BACKEND_CACHE=""
    echo 'OK: NETFILTER_BACKEND selects tools and rejects unknown values'

    # --- снапшоты: ротация по возрасту и количеству ---
    local snap_old snap_new
    snap_old="$SNAPSHOT_DIR/20200101-000000"
    snap_new="$SNAPSHOT_DIR/$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$snap_old" "$snap_new"
    printf 'create X hash:net\n' > "$snap_old/sets"
    touch -d '60 days ago' "$snap_old"
    set_setting SNAPSHOT_KEEP 1 >/dev/null
    set_setting SNAPSHOT_MAX_AGE_DAYS 30 >/dev/null
    snapshot_state >/dev/null
    [[ ! -d "$snap_old" ]] || { echo "FAIL: snapshot older than max age was kept" >&2; return 1; }
    [[ -d "$snap_new" ]] || { echo "FAIL: recent snapshot was removed" >&2; return 1; }
    echo 'OK: snapshot rotation removes only dirs older than SNAPSHOT_MAX_AGE_DAYS'

    # --- регрессия: сбой ipset restore не должен выглядеть как успешное обновление ---
    export MOCK_IPSET_RESTORE_FAIL=1
    if update_tspublock_list >/dev/null 2>&1; then
        unset MOCK_IPSET_RESTORE_FAIL
        echo 'FAIL: update_tspublock_list returned success when ipset restore failed' >&2
        return 1
    fi
    unset MOCK_IPSET_RESTORE_FAIL
    echo 'OK: ipset restore failure propagates as update error'

    set_setting ENABLE_TSPUBLOCK n >/dev/null
    set_setting ENABLE_GOVIPS n >/dev/null
    setup_tspublock_rules
    setup_govips_rules
    python3 - <<'PY'
import json, os
state = json.load(open(os.path.join(os.environ['STATE'], 'iptables.json')))
assert '-j TSPUBLOCK' not in state['chains']['INPUT']
assert '-j GOVBLOCK' not in state['chains']['INPUT']
assert state['chains']['TSPUBLOCK'] == []
assert state['chains']['GOVBLOCK'] == []
print('OK: disabling clears TSPUBLOCK/GOVIPS hooks and chains')
PY

    set_setting ENABLE_TSPUBLOCK y >/dev/null
    set_setting ENABLE_GOVIPS y >/dev/null
    setup_tspublock_rules
    setup_govips_rules
    python3 - <<'PY'
import json, os
ipt_path = os.path.join(os.environ['STATE'], 'iptables.json')
ipset_path = os.path.join(os.environ['STATE'], 'ipset.json')
ipt = json.load(open(ipt_path))
ipsets = json.load(open(ipset_path))
ipt['chains']['INPUT'].insert(0, '-m comment --comment rkn-watcher-geoip-hook -j RKN_GEOIP_HOOK')
ipt['chains']['RKN_GEOIP_HOOK'] = ['-j GEOIP_DROP']
ipt['chains']['GEOIP_DROP'] = ['-j DROP']
ipsets['GEOIP_ALLOW_IPS'] = ['1.1.1.1']
ipsets['GEOIP_DENY_IPS'] = ['2.2.2.2']
ipsets['GEOIP_COUNTRIES_ALLOW'] = ['5.5.5.0/24']
json.dump(ipt, open(ipt_path, 'w'))
json.dump(ipsets, open(ipset_path, 'w'))
PY
    remove_managed_firewall
    python3 - <<'PY'
import json, os
ipt = json.load(open(os.path.join(os.environ['STATE'], 'iptables.json')))
for token in ['-j TSPUBLOCK', '-j GOVBLOCK', '-m comment --comment rkn-watcher-geoip-hook -j RKN_GEOIP_HOOK']:
    assert token not in ipt['chains']['INPUT'], ipt['chains']['INPUT']
for chain in ['TSPUBLOCK', 'GOVBLOCK', 'RKN_GEOIP_HOOK', 'GEOIP_DROP']:
    assert chain not in ipt['chains'] or ipt['chains'][chain] == []
ipsets = json.load(open(os.path.join(os.environ['STATE'], 'ipset.json')))
for name in ['TSPUIPS', 'GOVIPS', 'GEOIP_ALLOW_IPS', 'GEOIP_DENY_IPS', 'GEOIP_COUNTRIES_ALLOW']:
    assert name not in ipsets
print('OK: remove_managed_firewall removes hooks, chains and sets')
PY
}

run_release_metadata_tests() {
    local version
    version=$(tr -d '\r\n' < "$REPO_ROOT/VERSION")
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
    grep -Fq "VERSION=\"$version\"" "$REPO_ROOT/lib/config.sh"
    if ! grep -Fq "# RKN Watcher v$version" "$REPO_ROOT/README.md"; then
        printf 'FAIL: README.md не содержит "# RKN Watcher v%s"\n' "$version" >&2
        return 1
    fi
    grep -Fq "# RKN Watcher v$version" "$REPO_ROOT/README.md"
    grep -Fq "# RKN Watcher v$version" "$REPO_ROOT/README.en.md"
    grep -Fq "# RKN Watcher v$version" "$REPO_ROOT/README.ru.md"
    grep -Fq "# Release Notes — RKN Watcher v$version" "$REPO_ROOT/RELEASE_NOTES.en.md"
    grep -Fq "v$version" "$REPO_ROOT/CHANGELOG.en.md"
    grep -Fq "v$version" "$REPO_ROOT/CHANGELOG.ru.md"
    printf 'OK: release metadata consistently declares v%s\n' "$version"
}

run_installer_nft_tests() {
    # Установщик должен требовать установленный и включённый nftables.
    local root="$TMP_ROOT/installer-nft"
    mkdir -p "$root/bin" "$root/app"
    cp "$REPO_ROOT/installer.sh" "$root/app/installer.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$root/app/rkn-watcher.sh"
    chmod +x "$root/app/rkn-watcher.sh"

    # dpkg-query сообщает, что все зависимости, включая nftables, установлены
    cat > "$root/bin/dpkg-query" <<'PY'
#!/usr/bin/env bash
[[ "${3:-}" == "nftables" ]] && { printf 'install ok installed'; exit 0; }
printf 'install ok installed'
PY
    # nft: ruleset пуст, конфиг с правилами есть -> установщик должен это заметить
    cat > "$root/bin/nft" <<'PY'
#!/usr/bin/env bash
state="${NFT_STATE:-empty}"
case "$1 $2" in
    "list ruleset")
        if [[ "$state" == "full" ]]; then
            printf 'table inet filter {\n\tchain input {\n\t\ttype filter hook input priority 0; policy accept;\n\t\tct state established,related accept\n\t}\n}\n'
        fi
        ;;
    "list tables")
        [[ "$state" == "full" ]] && printf 'table inet filter\n'
        ;;
    "--version"|"list")
        echo "nftables v1.0.6 (Lester Gooch)"
        ;;
esac
exit 0
PY
    printf '#!/usr/bin/env bash\n[[ "$1" == "is-enabled" || "$1" == "is-active" ]] && { echo inactive; exit 3; }\nexit 0\n' > "$root/bin/systemctl"
    printf '#!/usr/bin/env bash\necho /usr/sbin/iptables-nft\n' > "$root/bin/readlink"
    chmod +x "$root"/bin/*

    local conf="$root/nftables.conf"
    printf 'flush ruleset\ntable inet filter {\n}\n' > "$conf"

    # Собираем installer.sh с изолированным окружением: пути и systemctl — мок
    python3 - "$root" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
src = (root / 'app' / 'installer.sh').read_text()
src = src.replace('STATE_DIR="/var/lib/rkn-watcher/state"', f'STATE_DIR="{root}/state"')
src = src.replace('PKG_MANIFEST="$STATE_DIR/installer-packages.txt"', f'PKG_MANIFEST="{root}/state/installer-packages.txt"')
src = src.replace('main "$@"', '')
src += '\n"$@"\n'
(root / 'app' / 'lib.sh').write_text(src)
PY

    local out rc
    out=$(PATH="$root/bin:$PATH" NFT_STATE=empty NFTABLES_CONF="$conf" STATE="$root/state" \
        bash -c "source '$root/app/lib.sh'; ensure_nftables n" 2>&1) && rc=0 || rc=$?

    grep -q "nftables установлен" <<<"$out" || { echo "FAIL: installer does not report nftables package state" >&2; echo "$out" >&2; return 1; }
    grep -qE "пуст" <<<"$out" || { echo "FAIL: installer does not warn about empty nftables ruleset" >&2; echo "$out" >&2; return 1; }
    grep -qE "nft-бэкенд|legacy-бэкенд" <<<"$out" || { echo "FAIL: installer does not report the iptables backend" >&2; echo "$out" >&2; return 1; }
    [[ "$rc" -eq 0 ]] || { echo "FAIL: ensure_nftables failed on a healthy system (rc=$rc)" >&2; echo "$out" >&2; return 1; }
    echo "OK: installer verifies nftables package, ruleset and iptables backend"

    # nft есть, ruleset загружен -> успех без предупреждений про пустой ruleset
    out=$(PATH="$root/bin:$PATH" NFT_STATE=full NFTABLES_CONF="$conf" STATE="$root/state" \
        bash -c "source '$root/app/lib.sh'; ensure_nftables n" 2>&1) || true
    grep -qE "ruleset nftables загружен" <<<"$out" || { echo "FAIL: loaded nftables ruleset not reported" >&2; echo "$out" >&2; return 1; }
    echo "OK: installer reports a loaded nftables ruleset"

    # nftables отсутствует и утилиты nft нет: без интерактивного режима это ошибка
    rm -f "$root/bin/nft"
    cat > "$root/bin/dpkg-query" <<'PY'
#!/usr/bin/env bash
[[ "${3:-}" == "nftables" ]] && { printf 'deinstall ok config-files'; exit 0; }
printf 'install ok installed'
PY
    chmod +x "$root/bin/dpkg-query"
    local rc_missing=0
    out=$(PATH="$root/bin:/usr/bin:/bin" STATE="$root/state" \
        bash -c "source '$root/app/lib.sh'; ensure_nftables n" 2>&1) || rc_missing=$?
    grep -q "nftables не установлен" <<<"$out" || { echo "FAIL: missing nftables was not reported" >&2; echo "$out" >&2; return 1; }
    [[ "$rc_missing" -ne 0 ]] || { echo "FAIL: ensure_nftables returned success without nftables" >&2; return 1; }
    echo "OK: installer fails when nftables is missing"
}

run_config_tool_tests() {
    local root="$TMP_ROOT/config-tool"
    mkdir -p "$root/etc"

    python3 - "$REPO_ROOT/config_tool.py" "$root/config_tool.py" "$root" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text()
root = sys.argv[3]
src = src.replace(
    'WHITELIST_FILE = "/etc/rkn-watcher/whitelist.json"',
    f'WHITELIST_FILE = r"{root}/etc/whitelist.json"',
)
src = src.replace(
    'BLACKLIST_FILE = "/etc/rkn-watcher/blacklist.json"',
    f'BLACKLIST_FILE = r"{root}/etc/blacklist.json"',
)
Path(sys.argv[2]).write_text(src)
PY

    cat > "$root/etc/whitelist.json" <<'EOF2'
{
  "enabled": "false",
  "countries": [],
  "ips": [],
  "ports": []
}
EOF2

    [[ "$(python3 "$root/config_tool.py" get-enabled)" == "false" ]]
    python3 "$root/config_tool.py" add-country FI >/dev/null
    local countries=(US DE FR JP CA AU BR MX IN GB)
    local country pid
    local pids=()
    for country in "${countries[@]}"; do
        python3 "$root/config_tool.py" add-country "$country" >/dev/null &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    python3 "$root/config_tool.py" add-ip 192.0.2.1 >/dev/null
    python3 "$root/config_tool.py" add-ip 2001:db8::1 >/dev/null || {
        echo 'FAIL: config_tool rejected an IPv6 address' >&2
        return 1
    }
    if python3 "$root/config_tool.py" add-ip 2001:db8:::1 >/dev/null 2>&1; then
        echo 'FAIL: config_tool accepted a malformed address' >&2
        return 1
    fi
    python3 - "$root/etc/whitelist.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as fh:
    data = json.load(fh)
assert data['enabled'] is False
assert data['countries'] == sorted(['FI', 'US', 'DE', 'FR', 'JP', 'CA', 'AU', 'BR', 'MX', 'IN', 'GB'])
assert data['ips'] == ['192.0.2.1', '2001:db8::1'], data['ips']
print('OK: config tool keeps concurrent updates, normalizes legacy booleans, accepts IPv4+IPv6')
PY
}

run_geoip_tests() {
    local root="$TMP_ROOT/geoip"
    mkdir -p "$root/bin" "$root/state" "$root/etc" "$root/cache/countries" "$root/log"
    export STATE="$root/state"

    create_fake_iptables "$root/bin/iptables"
    create_fake_ip6tables_iptables "$root/bin/iptables"
    create_fake_iptables_restore "$root/bin/iptables-restore"
    create_fake_iptables_save "$root/bin/iptables-save"
    create_fake_ipset "$root/bin/ipset"
    create_fake_ipset_save "$root/bin/ipset-save"
    export PATH="$root/bin:$PATH"

    python3 - "$REPO_ROOT/geoip_apply.py" "$root/geoip_apply.py" "$root" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text()
root = sys.argv[3]
replacements = {
    'CONFIG_FILE = "/etc/rkn-watcher/whitelist.json"': f'CONFIG_FILE = r"{root}/etc/whitelist.json"',
    'BLACKLIST_FILE = "/etc/rkn-watcher/blacklist.json"': f'BLACKLIST_FILE = r"{root}/etc/blacklist.json"',
    'SETTINGS_FILE = "/etc/rkn-watcher/settings.conf"': f'SETTINGS_FILE = r"{root}/etc/settings.conf"',
    'CACHE_DIR = "/var/lib/rkn-watcher/cache/countries"': f'CACHE_DIR = r"{root}/cache/countries"',
    'LOG_FILE = "/var/log/rkn-watcher/geoip.log"': f'LOG_FILE = r"{root}/log/geoip.log"',
}
for old, new in replacements.items():
    src = src.replace(old, new)
Path(sys.argv[2]).write_text(src)
PY

    cat > "$root/etc/settings.conf" <<'EOF2'
FILTER_PORTS="443,80"
EOF2
    cat > "$root/etc/whitelist.json" <<'EOF2'
{
  "enabled": true,
  "countries": ["FI"],
  "ips": ["1.1.1.1", "10.0.0.0/24"],
  "ports": [22, 443]
}
EOF2
    cat > "$root/etc/blacklist.json" <<'EOF2'
{
  "ips": ["2.2.2.2"],
  "ports": [25]
}
EOF2
    echo '5.5.5.0/24' > "$root/cache/countries/fi.zone"

    python3 "$root/geoip_apply.py" apply >/dev/null
    python3 - <<'PY'
import json, os
root = os.path.join(os.environ['STATE'], 'iptables.json')
state = json.load(open(root))
assert state['chains']['INPUT'].count('-m comment --comment rkn-watcher-geoip-hook -j RKN_GEOIP_HOOK') == 1
hook = state['chains']['RKN_GEOIP_HOOK']
hook_text = ' | '.join(hook)
assert hook_text.startswith('-i lo -j RETURN'), hook
assert '-m conntrack --ctstate ESTABLISHED,RELATED -j RETURN' in hook_text, hook
# deny-стадия работает независимо от FILTER_PORTS
assert any('rkn-watcher-deny' in r and 'RKN_DENY' in r for r in hook), hook
assert 'rkn-watcher-geoip' in ' '.join(hook), hook
action = state['chains']['GEOIP_DROP']
deny_chain = state['chains']['RKN_DENY']
# deny IP и deny-порт (25) живут в отдельной стадии и не зависят от FILTER_PORTS
assert deny_chain[0] == '-m set --match-set GEOIP_DENY_IPS src -j DROP', deny_chain
assert any('--dports 25' in r and r.endswith('-j DROP') for r in deny_chain), deny_chain
assert action[0] == '-m set --match-set GEOIP_ALLOW_IPS src -j RETURN', action
assert '-m set --match-set GEOIP_COUNTRIES_ALLOW src -j RETURN' in action
assert action[-1] == '-j DROP'
sets = json.load(open(os.path.join(os.environ['STATE'], 'ipset.json')))
assert sorted(sets['GEOIP_ALLOW_IPS']) == ['1.1.1.1', '10.0.0.0/24']
assert sets['GEOIP_DENY_IPS'] == ['2.2.2.2']
assert sets['GEOIP_COUNTRIES_ALLOW'] == ['5.5.5.0/24']
print('OK: geoip apply creates expected rules and sets')
PY

    python3 "$root/geoip_apply.py" apply >/dev/null
    python3 - <<'PY'
import json, os
state = json.load(open(os.path.join(os.environ['STATE'], 'iptables.json')))
assert state['chains']['INPUT'].count('-m comment --comment rkn-watcher-geoip-hook -j RKN_GEOIP_HOOK') == 1
print('OK: geoip reapply does not duplicate INPUT hook')
PY

    cat > "$root/etc/whitelist.json" <<'EOF2'
{
  "enabled": false,
  "countries": ["FI"],
  "ips": ["1.1.1.1"],
  "ports": [22]
}
EOF2
    python3 "$root/geoip_apply.py" apply >/dev/null
    python3 - <<'PY'
import json, os
state = json.load(open(os.path.join(os.environ['STATE'], 'iptables.json')))
# GeoIP выключен: страновой фильтр и allow-логика сняты,
# но blacklist (deny) продолжает работать — это блок-лист, а не страновой фильтр.
hook = ' | '.join(state['chains']['RKN_GEOIP_HOOK'])
assert 'GEOIP_DROP' not in hook, hook
assert state['chains']['GEOIP_DROP'] == [], state['chains']['GEOIP_DROP']
assert any('GEOIP_DENY_IPS' in r for r in state['chains']['RKN_DENY'])
print('OK: disabling geoip clears country filtering but keeps deny stage')
PY

    # IPv6 для allow/deny-списков: адреса уходят в inet6-наборы и ip6tables
    cat > "$root/etc/settings.conf" <<'EOF2'
FILTER_PORTS="all"
EOF2
    cat > "$root/etc/whitelist.json" <<'EOF2'
{"enabled": false, "countries": [], "ips": ["192.0.2.10", "2001:db8::/32"], "ports": []}
EOF2
    cat > "$root/etc/blacklist.json" <<'EOF2'
{"ips": ["198.51.100.10", "2001:db8:dead::/48"], "ports": []}
EOF2
    python3 "$root/geoip_apply.py" apply >/dev/null
    python3 - <<'PY'
import json, os
state = os.environ['STATE']
sets = json.load(open(os.path.join(state, 'ipset.json')))
assert sets['GEOIP_ALLOW_IPS'] == ['192.0.2.10'], sets.get('GEOIP_ALLOW_IPS')
assert sets['GEOIP_DENY_IPS'] == ['198.51.100.10'], sets.get('GEOIP_DENY_IPS')
assert sets['GEOIP_ALLOW_IPS6'] == ['2001:db8::/32'], sets.get('GEOIP_ALLOW_IPS6')
assert sets['GEOIP_DENY_IPS6'] == ['2001:db8:dead::/48'], sets.get('GEOIP_DENY_IPS6')
v6 = json.load(open(os.path.join(state, 'iptables6.json')))
hook6 = v6['chains'].get('RKN_GEOIP_HOOK6', [])
deny6 = v6['chains'].get('RKN_DENY', [])
# deny-стадия в v6 создаётся, когда GeoIP выключен, но есть deny-список
assert any('GEOIP_DENY_IPS6' in r for r in deny6), deny6
assert '-m comment --comment rkn-watcher-geoip-hook -j RKN_GEOIP_HOOK6' in v6['chains']['INPUT'], v6['chains']['INPUT']
print('OK: allow/deny IPv6 entries land in inet6 sets and ip6tables')
PY

    # некорректный адрес в списке — явная ошибка
    cat > "$root/etc/whitelist.json" <<'EOF2'
{"enabled": false, "countries": [], "ips": ["2001:db8:::1"], "ports": []}
EOF2
    if python3 "$root/geoip_apply.py" apply >/dev/null 2>&1; then
        echo 'FAIL: invalid IPv6 entry accepted' >&2
        return 1
    fi
    echo 'OK: invalid address in allow/deny list is a config error'

    # PORT_POLICY=strict: открыты только порты из FILTER_PORTS
    cat > "$root/etc/settings.conf" <<'EOF2'
FILTER_PORTS="443,80"
PORT_POLICY="strict"
EOF2
    cat > "$root/etc/whitelist.json" <<'EOF2'
{"enabled": true, "countries": ["FI"], "ips": [], "ports": []}
EOF2
    python3 "$root/geoip_apply.py" apply >/dev/null
    python3 - <<'PY'
import json, os
state = json.load(open(os.path.join(os.environ['STATE'], 'iptables.json')))
protect = state['chains']['RKN_PROTECT']
assert '-p tcp -m multiport --dports 80,443 -j RETURN' in protect, protect
assert '-p udp -m multiport --dports 80,443 -j RETURN' in protect, protect
assert protect[-1] == '-j DROP', protect
print('OK: PORT_POLICY=strict closes everything outside FILTER_PORTS')
PY

    # dry-run не должен ничего менять в системе
    local before_after_before before_after_after
    before_after_before=$(cat "$STATE/iptables.json")
    python3 "$root/geoip_apply.py" apply --dry-run >/dev/null
    before_after_after=$(cat "$STATE/iptables.json")
    [[ "$before_after_before" == "$before_after_after" ]] || { echo 'FAIL: --dry-run modified firewall state' >&2; return 1; }
    echo 'OK: apply --dry-run does not touch firewall state'

    # некорректный FILTER_PORTS даёт понятную ошибку, а не трейсбек
    printf 'FILTER_PORTS="443;80"\n' > "$root/etc/settings.conf"
    if python3 "$root/geoip_apply.py" apply >/dev/null 2>"$root/err.txt"; then
        echo 'FAIL: invalid FILTER_PORTS accepted' >&2
        return 1
    fi
    grep -q 'FILTER_PORTS' "$root/err.txt" || { echo "FAIL: error message does not mention FILTER_PORTS" >&2; cat "$root/err.txt" >&2; return 1; }
    echo 'OK: invalid FILTER_PORTS produces a readable config error'
    printf 'FILTER_PORTS="443,80"\n' > "$root/etc/settings.conf"

    # пустые списки + выключенный GeoIP: хук в INPUT не нужен вовсе
    cat > "$root/etc/whitelist.json" <<'EOF2'
{"enabled": false, "countries": [], "ips": [], "ports": []}
EOF2
    cat > "$root/etc/blacklist.json" <<'EOF2'
{"ips": [], "ports": []}
EOF2
    python3 "$root/geoip_apply.py" apply >/dev/null
    python3 - <<'PY'
import json, os
state = json.load(open(os.path.join(os.environ['STATE'], 'iptables.json')))
assert '-m comment --comment rkn-watcher-geoip-hook -j RKN_GEOIP_HOOK' not in state['chains']['INPUT'], state['chains']['INPUT']
print('OK: no INPUT hook when there is nothing to enforce')
PY

    cat > "$root/etc/blacklist.json" <<'EOF2'
{"ips": ["2.2.2.2"], "ports": [25]}
EOF2
    python3 - "$root/etc/whitelist.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path, encoding='utf-8') as fh:
    data = json.load(fh)
data['enabled'] = 'false'
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh)
PY
    python3 "$root/geoip_apply.py" apply >/dev/null
    python3 - <<'PY'
import json, os
state = json.load(open(os.path.join(os.environ['STATE'], 'iptables.json')))
assert state['chains']['GEOIP_DROP'] == [], state['chains']['GEOIP_DROP']
print('OK: geoip handles legacy false string as disabled')
PY
}

main() {
    extract_bash_lib
    run_release_metadata_tests
    run_bash_logic_tests
    run_installer_nft_tests
    run_config_tool_tests
    run_geoip_tests
    echo
    echo 'All tests passed.'
}

main "$@"
