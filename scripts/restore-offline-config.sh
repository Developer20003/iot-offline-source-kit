#!/usr/bin/env bash
set -euo pipefail
umask 077

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$KIT_ROOT/offline-bundle/config"

files=(
    "compose.yaml"
    "runtime/compose/thingsboard.env"
    "runtime/kafka/config/server.properties"
    "runtime/zigbee2mqtt/configuration.template.yaml"
    "runtime/postgres/postgres.env.example"
    "runtime/emqx/emqx.env.example"
)

verify_config() {
    echo "=== VERIFY PORTABLE CONFIGURATION ==="

    (
        cd "$CONFIG"
        sha256sum -c SHA256SUMS
    )

    echo "PORTABLE CONFIGURATION: VERIFIED"
}

if [[ "${1:-}" == "--verify" && $# -eq 1 ]]; then
    verify_config
    exit 0
fi

if [[ "${1:-}" != "--restore" || $# -ne 2 ]]; then
    echo "Usage:"
    echo "  $0 --verify"
    echo "  $0 --restore /path/to/restored-kit"
    exit 1
fi

TARGET="$(realpath -m -- "$2")"

case "$TARGET" in
    "$KIT_ROOT"|"$KIT_ROOT"/*)
        echo "ERROR: Cannot overwrite the original kit."
        exit 1
        ;;
esac

if [[ ! -d "$TARGET/sources" ]]; then
    echo "ERROR: Restore source repositories first."
    exit 1
fi

echo "=== CHECK CONFIGURATION DESTINATIONS ==="

for file in "${files[@]}"; do
    if [[ -e "$TARGET/$file" || -L "$TARGET/$file" ]]; then
        echo "ERROR: File already exists: $TARGET/$file"
        exit 1
    fi

    if [[ -L "$(dirname "$TARGET/$file")" ]]; then
        echo "ERROR: Destination directory is a symbolic link."
        exit 1
    fi
done

verify_config

echo
echo "=== RESTORE CONFIGURATION FILES ==="

for file in "${files[@]}"; do
    mkdir -p "$(dirname "$TARGET/$file")"

    cp -- "$CONFIG/$file" "$TARGET/$file"

    echo "RESTORED: $file"
done

echo
echo "=== VERIFY RESTORED FILES ==="

for file in "${files[@]}"; do
    cmp -s "$CONFIG/$file" "$TARGET/$file"
    echo "PASS: $file"
done

echo
echo "OFFLINE CONFIGURATION RESTORATION: PASS"
echo "Private credentials: NOT GENERATED"
echo "Docker containers: NOT STARTED"
