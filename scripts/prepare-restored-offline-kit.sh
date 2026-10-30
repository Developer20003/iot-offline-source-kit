#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_scripts=(
    restore-offline-docker-images.sh
    prepare-offline-docker-resources.sh
    init-offline-kafka.sh
)

verify_scripts() {
    echo "=== VERIFY INSTALLATION SCRIPTS ==="

    for script in "${required_scripts[@]}"; do
        test -f "$KIT_ROOT/scripts/$script"
        bash -n "$KIT_ROOT/scripts/$script"
        echo "PASS: $script"
    done

    echo
    echo "=== VERIFY DOCKER IMAGE ARCHIVES ==="

    bash "$KIT_ROOT/scripts/restore-offline-docker-images.sh" \
        --verify

    echo
    echo "OFFLINE PREPARATION VERIFICATION: PASS"
}

if [[ "${1:-}" == "--verify" && $# -eq 1 ]]; then
    verify_scripts
    exit 0
fi

if [[ "${1:-}" != "--prepare" || $# -ne 2 ]]; then
    echo "Usage:"
    echo "  $0 --verify"
    echo "  $0 --prepare /path/to/restored-kit"
    exit 1
fi

TARGET="$(realpath -m -- "$2")"

case "$TARGET" in
    "$KIT_ROOT"|"$KIT_ROOT"/*)
        echo "ERROR: Cannot prepare the original kit."
        exit 1
        ;;
esac

echo "=== CHECK RESTORED DEVELOPMENT KIT ==="

required_files=(
    compose.yaml
    runtime/postgres/postgres.env
    runtime/emqx/emqx.env
    runtime/compose/thingsboard.env
    runtime/kafka/config/server.properties
    runtime/kafka/distribution/bin/kafka-storage.sh
    sources/thingsboard/application/target/thingsboard-4.3.1.6-boot.jar
    sources/emqx/_build/emqx-enterprise/rel/emqx/bin/emqx
    gateway/ble_gateway.py
)

for file in "${required_files[@]}"; do
    if [[ ! -s "$TARGET/$file" ]]; then
        echo "ERROR: Missing restored file: $file"
        exit 1
    fi
done

echo "RESTORED DEVELOPMENT FILES: PASS"

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker Engine is unavailable."
    exit 1
fi

echo
echo "=== VALIDATE RESTORED DOCKER COMPOSE ==="

docker compose \
    --project-directory "$TARGET" \
    -f "$TARGET/compose.yaml" \
    config --quiet

echo "RESTORED DOCKER COMPOSE: PASS"

echo
echo "=== CHECK EXISTING CONTAINER CONFLICTS ==="

for name in \
    iot-postgres \
    iot-emqx \
    iot-kafka \
    iot-thingsboard; do

    if docker container inspect "$name" >/dev/null 2>&1; then
        echo "ERROR: Container $name already exists."
        echo "Existing containers will not be replaced."
        exit 1
    fi
done

echo "CONTAINER NAME CONFLICTS: NONE"

echo
echo "=== CHECK EXISTING DOCKER RESOURCES ==="

for spec in "network:iot-backend" "volume:iot-postgres-data"; do
    kind="${spec%%:*}"
    name="${spec#*:}"

    if docker "$kind" inspect "$name" >/dev/null 2>&1; then
        owner="$(docker "$kind" inspect \
            --format '{{index .Labels "offline.iot-kit.managed"}}' \
            "$name")"

        if [[ "$owner" != "true" ]]; then
            echo "ERROR: Unmanaged Docker $kind exists: $name"
            echo "No resources will be replaced."
            exit 1
        fi
    fi
done

echo "DOCKER RESOURCE CONFLICTS: NONE"

echo
echo "=== VERIFY OFFLINE INSTALLATION ARCHIVES ==="

verify_scripts

echo
echo "=== LOAD DOCKER IMAGES ==="

bash "$KIT_ROOT/scripts/restore-offline-docker-images.sh" \
    --load

echo
echo "=== CREATE DOCKER NETWORK AND STORAGE ==="

bash "$KIT_ROOT/scripts/prepare-offline-docker-resources.sh" \
    --prepare "$TARGET"

echo
echo "=== INITIALIZE KAFKA KRAFT STORAGE ==="

bash "$KIT_ROOT/scripts/init-offline-kafka.sh" \
    --init "$TARGET"

echo
echo "OFFLINE ENVIRONMENT PREPARATION: PASS"
echo "PostgreSQL database: NOT YET RESTORED"
echo "Application containers: NOT STARTED"
