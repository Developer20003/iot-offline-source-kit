#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != "--init" || $# -ne 2 ]]; then
    echo "Usage: $0 --init /path/to/restored-kit"
    exit 1
fi

TARGET="$(realpath -m -- "$2")"

case "$TARGET" in
    "$KIT_ROOT"|"$KIT_ROOT"/*)
        echo "ERROR: Cannot initialize Kafka in the original kit."
        exit 1
        ;;
esac

KAFKA="$TARGET/runtime/kafka/distribution"
CONFIG="$TARGET/runtime/kafka/config/server.properties"
DATA="$TARGET/runtime/kafka/data"
META="$DATA/meta.properties"

if [[ ! -x "$KAFKA/bin/kafka-storage.sh" ]]; then
    echo "ERROR: Kafka distribution is missing."
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: Kafka server.properties is missing."
    exit 1
fi

if ! grep -Eq '^[[:space:]]*log.dirs[[:space:]]*=[[:space:]]*/var/lib/kafka/data[[:space:]]*$' "$CONFIG"; then
    echo "ERROR: Kafka log.dirs does not match the expected data mount."
    exit 1
fi

if [[ -f "$META" ]]; then
    echo "KAFKA STORAGE: ALREADY INITIALIZED (SKIPPED)"
    exit 0
fi

if [[ -d "$DATA" ]] &&
   [[ -n "$(find "$DATA" -mindepth 1 -print -quit)" ]]; then
    echo "ERROR: Kafka data directory is not empty."
    echo "Existing data will not be reformatted."
    exit 1
fi

docker image inspect eclipse-temurin:17-jdk >/dev/null

mkdir -p "$DATA"

echo "=== INITIALIZE KAFKA KRAFT STORAGE OFFLINE ==="

docker run --rm \
    --network none \
    --pull=never \
    --hostname iot-kafka \
    --user "$(id -u):$(id -g)" \
    --entrypoint /bin/bash \
    -e LOG_DIR=/tmp/kafka-logs \
    -v "$KAFKA:/opt/kafka:ro" \
    -v "$(dirname "$CONFIG"):/etc/kafka:ro" \
    -v "$DATA:/var/lib/kafka/data" \
    -w /opt/kafka \
    eclipse-temurin:17-jdk \
    -lc '
        set -e

        cluster_id="$(bin/kafka-storage.sh random-uuid)"

        bin/kafka-storage.sh format \
            --standalone \
            -t "$cluster_id" \
            -c /etc/kafka/server.properties
    '

echo
echo "=== VERIFY KAFKA STORAGE METADATA ==="

test -s "$META"
grep -q '^cluster.id=' "$META"
grep -q '^node.id=1$' "$META"

echo "KAFKA KRAFT STORAGE INITIALIZATION: PASS"
echo "Existing Kafka containers: UNCHANGED"
