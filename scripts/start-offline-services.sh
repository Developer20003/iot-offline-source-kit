#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -ne 2 ]]; then
    echo "Usage:"
    echo "  $0 --verify /path/to/kit"
    echo "  $0 --start /path/to/restored-kit"
    exit 1
fi

MODE="$1"

case "$MODE" in
    --verify|--start) ;;
    *)
        echo "ERROR: Invalid mode."
        exit 1
        ;;
esac

TARGET="$(realpath -e -- "$2")"

echo "=== VERIFY OFFLINE APPLICATION FILES ==="

required=(
    compose.yaml
    runtime/postgres/postgres.env
    runtime/emqx/emqx.env
    runtime/compose/thingsboard.env
    runtime/kafka/config/server.properties
    runtime/kafka/data/meta.properties
    runtime/kafka/distribution/bin/kafka-server-start.sh
    sources/emqx/_build/emqx-enterprise/rel/emqx/bin/emqx
    sources/thingsboard/application/target/thingsboard-4.3.1.6-boot.jar
)

for file in "${required[@]}"; do
    if [[ ! -s "$TARGET/$file" ]]; then
        echo "ERROR: Missing file: $file"
        exit 1
    fi
done

echo "APPLICATION FILES: PASS"

echo
echo "=== VERIFY DOCKER COMPOSE ==="

docker compose \
    --project-directory "$TARGET" \
    -f "$TARGET/compose.yaml" \
    config --quiet

echo "DOCKER COMPOSE: PASS"

echo
echo "=== VERIFY LOCAL DOCKER IMAGES ==="

images=(
    "postgres:17"
    "eclipse-temurin:17-jdk"
    "maven:3.9.9-eclipse-temurin-17"
    "ghcr.io/emqx/emqx-builder/6.1-8:1.19.1-28.4.1-4-ubuntu24.04"
)

for image in "${images[@]}"; do
    docker image inspect "$image" >/dev/null
    echo "AVAILABLE: $image"
done

echo "OFFLINE STARTUP REQUIREMENTS: PASS"

if [[ "$MODE" == "--verify" ]]; then
    echo
    echo "STARTUP SCRIPT VERIFICATION: PASS"
    echo "Containers: NOT STARTED"
    exit 0
fi

# Starting services is permitted only from a restored kit.
if [[ "$TARGET" == "$KIT_ROOT" ||
      "$TARGET" == "$KIT_ROOT/"* ]]; then
    echo "ERROR: Starting the original kit is prohibited."
    exit 1
fi

echo
echo "=== CHECK CONTAINER NAME CONFLICTS ==="

for name in \
    iot-postgres \
    iot-emqx \
    iot-kafka \
    iot-thingsboard; do

    if docker container inspect "$name" >/dev/null 2>&1; then
        echo "ERROR: Container already exists: $name"
        echo "Existing containers will not be replaced."
        exit 1
    fi
done

echo "CONTAINER CONFLICTS: NONE"

echo
echo "=== VERIFY MANAGED DOCKER RESOURCES ==="

for spec in \
    "network:iot-backend" \
    "volume:iot-postgres-data"; do

    kind="${spec%%:*}"
    name="${spec#*:}"

    docker "$kind" inspect "$name" >/dev/null

    owner="$(
        docker "$kind" inspect \
            --format '{{index .Labels "offline.iot-kit.managed"}}' \
            "$name"
    )"

    if [[ "$owner" != "true" ]]; then
        echo "ERROR: Unmanaged Docker resource: $name"
        exit 1
    fi

    echo "VERIFIED: $name"
done

echo
echo "=== VERIFY POSTGRESQL DATA IS INITIALIZED ==="

pg_version="$(
    docker run --rm \
        --network none \
        --pull=never \
        --mount \
        type=volume,source=iot-postgres-data,target=/check,readonly,volume-nocopy \
        --entrypoint /bin/sh \
        postgres:17 \
        -ec 'cat /check/PG_VERSION'
)"

if [[ "$pg_version" != "17" ]]; then
    echo "ERROR: PostgreSQL 17 data is not initialized."
    echo "Restore the database before starting services."
    exit 1
fi

echo "POSTGRESQL DATA: READY"

echo
echo "=== START OFFLINE IOT SERVICES ==="

docker compose \
    --project-directory "$TARGET" \
    -f "$TARGET/compose.yaml" \
    up -d --no-build --pull never

echo
echo "=== SERVICE STATUS ==="

docker compose \
    --project-directory "$TARGET" \
    -f "$TARGET/compose.yaml" \
    ps

echo
echo "OFFLINE SERVICE START COMMAND: COMPLETED"
echo "Check individual service health before use."
