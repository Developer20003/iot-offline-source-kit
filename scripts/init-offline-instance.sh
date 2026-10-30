#!/usr/bin/env bash
set -euo pipefail
umask 077

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/restored-kit"
    exit 1
fi

TARGET="$(realpath -m -- "$1")"

case "$TARGET" in
    "$KIT_ROOT"|"$KIT_ROOT"/*)
        echo "ERROR: Cannot initialize the original development kit."
        exit 1
        ;;
esac

for file in \
    "$TARGET/compose.yaml" \
    "$TARGET/runtime/postgres/postgres.env.example" \
    "$TARGET/runtime/emqx/emqx.env.example" \
    "$TARGET/runtime/compose/thingsboard.env"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Missing configuration: $file"
        exit 1
    fi
done

for file in \
    "$TARGET/runtime/postgres/postgres.env" \
    "$TARGET/runtime/emqx/emqx.env"; do
    if [[ -e "$file" || -L "$file" ]]; then
        echo "ERROR: Private settings already exist."
        echo "No credentials were overwritten."
        exit 1
    fi
done

python3 - "$TARGET" <<'PY'
from pathlib import Path
import secrets
import sys

root = Path(sys.argv[1])

def read_env(path):
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, value = line.split("=", 1)
            values[key] = value
    return values

pg = read_env(
    root / "runtime/postgres/postgres.env.example"
)
tb = read_env(
    root / "runtime/compose/thingsboard.env"
)

database = pg["POSTGRES_DB"]
username = pg["POSTGRES_USER"]

if tb.get("SPRING_DATASOURCE_USERNAME") != username:
    raise SystemExit(
        "ERROR: PostgreSQL and ThingsBoard usernames differ."
    )

password = secrets.token_hex(24)
cookie = secrets.token_hex(32)

files = {
    root / "runtime/postgres/postgres.env":
        f"POSTGRES_DB={database}\n"
        f"POSTGRES_USER={username}\n"
        f"POSTGRES_PASSWORD={password}\n",

    root / "runtime/emqx/emqx.env":
        "EMQX_NODE_NAME=emqx@node1.emqx.local\n"
        "EMQX_NODE__DEFAULT_LISTENER_ADDRESS=all\n"
        f"EMQX_NODE__COOKIE={cookie}\n",
}

created = []

try:
    for path, content in files.items():
        with path.open("x", encoding="utf-8") as f:
            f.write(content)
        path.chmod(0o600)
        created.append(path)
except BaseException:
    for path in created:
        path.unlink()
    raise

print("POSTGRESQL PRIVATE CREDENTIALS: CREATED")
print("EMQX PRIVATE CREDENTIALS: CREATED")
print("CREDENTIAL FILE PERMISSIONS: 600")
PY

mkdir -p \
    "$TARGET/runtime/emqx/data" \
    "$TARGET/runtime/kafka/data" \
    "$TARGET/runtime/thingsboard/install-data" \
    "$TARGET/logs/emqx" \
    "$TARGET/logs/kafka"

echo "OFFLINE INSTANCE INITIALIZATION: PASS"
echo "Docker containers: NOT STARTED"
