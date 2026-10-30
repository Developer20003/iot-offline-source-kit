#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVES="$KIT_ROOT/offline-bundle/runtime"

verify_archives() {
    echo "=== VERIFY RUNTIME ARCHIVES ==="
    (
        cd "$ARCHIVES"
        sha256sum -c SHA256SUMS
    )
    echo "RUNTIME ARCHIVES: VERIFIED"
}

if [[ "${1:-}" == "--verify" && $# -eq 1 ]]; then
    verify_archives
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
        echo "ERROR: Cannot restore over the original kit."
        exit 1
        ;;
esac

echo "=== CHECK RESTORED SOURCE DIRECTORIES ==="

for project in emqx kafka thingsboard zigbee2mqtt; do
    if [[ ! -d "$TARGET/sources/$project/.git" ]]; then
        echo "ERROR: Missing source repository: $project"
        exit 1
    fi
done

EMQX_BIN="$TARGET/sources/emqx/_build/emqx-enterprise/rel/emqx/bin/emqx"

if [[ ! -f "$EMQX_BIN" ]]; then
    echo "ERROR: EMQX release is missing."
    echo "Restore build resources first."
    exit 1
fi

TB_JAR="$TARGET/sources/thingsboard/application/target/thingsboard-4.3.1.6-boot.jar"
KAFKA_DIR="$TARGET/runtime/kafka/distribution"
ZIGBEE_DIR="$TARGET/sources/zigbee2mqtt/dist"
GATEWAY_DIR="$TARGET/gateway"

for path in "$TB_JAR" "$KAFKA_DIR" "$ZIGBEE_DIR" "$GATEWAY_DIR"; do
    if [[ -e "$path" || -L "$path" ]]; then
        echo "ERROR: Destination already exists: $path"
        exit 1
    fi
done

verify_archives

echo
echo "=== EXTRACT RUNTIME FILES TO STAGING ==="

STAGING="$(mktemp -d "$TARGET/.runtime-restore.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT

mkdir -p \
    "$STAGING/kafka" \
    "$STAGING/zigbee2mqtt" \
    "$STAGING/gateway"

cp "$ARCHIVES/thingsboard-4.3.1.6-boot.jar" \
   "$STAGING/thingsboard.jar"

tar -xzf "$ARCHIVES/kafka_2.13-4.2.2.tgz" \
    --strip-components=1 \
    -C "$STAGING/kafka"

tar -xzf "$ARCHIVES/zigbee2mqtt-2.14.2-build.tar.gz" \
    -C "$STAGING/zigbee2mqtt"

tar -xzf "$ARCHIVES/ble-gateway-source.tar.gz" \
    -C "$STAGING/gateway"

echo
echo "=== VERIFY EXTRACTED APPLICATIONS ==="

test -s "$STAGING/thingsboard.jar"
test -f "$STAGING/kafka/bin/kafka-server-start.sh"
test -d "$STAGING/zigbee2mqtt/dist"
test -f "$STAGING/gateway/ble_gateway.py"
test -f "$STAGING/gateway/requirements.txt"

echo "RUNTIME FILE VERIFICATION: PASS"

echo
echo "=== INSTALL COMPILED APPLICATIONS ==="

mkdir -p \
    "$(dirname "$TB_JAR")" \
    "$(dirname "$KAFKA_DIR")"

mv "$STAGING/thingsboard.jar" "$TB_JAR"
mv "$STAGING/kafka" "$KAFKA_DIR"
mv "$STAGING/zigbee2mqtt/dist" "$ZIGBEE_DIR"
mv "$STAGING/gateway" "$GATEWAY_DIR"

echo "THINGSBOARD RUNTIME RESTORE: PASS"
echo "EMQX RELEASE: PRESENT"
echo "KAFKA RUNTIME RESTORE: PASS"
echo "ZIGBEE2MQTT BUILD RESTORE: PASS"
echo "BLE GATEWAY SOURCE RESTORE: PASS"

echo
echo "OFFLINE RUNTIME RESTORATION: PASS"
