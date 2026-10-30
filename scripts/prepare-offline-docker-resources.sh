#!/usr/bin/env bash
set -euo pipefail

LABEL="offline.iot-kit.managed"
NETWORK="iot-backend"
VOLUME="iot-postgres-data"

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker Engine is unavailable."
    exit 1
fi

case "${1:-}" in

    --self-test)
        [[ $# -eq 1 ]] || exit 1

        TEST_NETWORK="iot-offline-test-net-$$"
        TEST_VOLUME="iot-offline-test-volume-$$"

        network_created=0
        volume_created=0

        cleanup() {
            if [[ "$volume_created" -eq 1 ]]; then
                docker volume rm "$TEST_VOLUME" >/dev/null
            fi

            if [[ "$network_created" -eq 1 ]]; then
                docker network rm "$TEST_NETWORK" >/dev/null
            fi
        }

        trap cleanup EXIT

        echo "=== TEST DOCKER NETWORK CREATION ==="

        docker network create \
            --driver bridge \
            --label "$LABEL=true" \
            "$TEST_NETWORK" >/dev/null

        network_created=1

        test "$(docker network inspect \
            --format '{{.Driver}}' "$TEST_NETWORK")" = "bridge"

        echo "TEMPORARY DOCKER NETWORK: PASS"

        echo
        echo "=== TEST DOCKER VOLUME CREATION ==="

        docker volume create \
            --label "$LABEL=true" \
            "$TEST_VOLUME" >/dev/null

        volume_created=1

        docker volume inspect "$TEST_VOLUME" >/dev/null

        echo "TEMPORARY POSTGRESQL VOLUME: PASS"

        echo
        echo "=== REMOVE TEST RESOURCES ==="

        cleanup
        trap - EXIT

        test "$(
            docker network inspect "$TEST_NETWORK" \
                >/dev/null 2>&1; echo $?
        )" != "0"

        test "$(
            docker volume inspect "$TEST_VOLUME" \
                >/dev/null 2>&1; echo $?
        )" != "0"

        echo "TEMPORARY RESOURCE CLEANUP: PASS"
        echo
        echo "OFFLINE DOCKER RESOURCE SELF-TEST: PASS"
        ;;

    --prepare)
        [[ $# -eq 2 ]] || exit 1

        TARGET="$(realpath -m -- "$2")"

        if [[ ! -f "$TARGET/compose.yaml" ]]; then
            echo "ERROR: Restore Docker Compose configuration first."
            exit 1
        fi

        echo "=== PREPARE OFFLINE DOCKER NETWORK ==="

        if docker network inspect "$NETWORK" >/dev/null 2>&1; then
            owner="$(docker network inspect \
                --format "{{index .Labels \"$LABEL\"}}" \
                "$NETWORK")"

            if [[ "$owner" != "true" ]]; then
                echo "ERROR: Existing network is not managed by this kit."
                exit 1
            fi

            echo "NETWORK: ALREADY PREPARED"
        else
            docker network create \
                --driver bridge \
                --label "$LABEL=true" \
                "$NETWORK" >/dev/null

            echo "NETWORK: CREATED"
        fi

        echo
        echo "=== PREPARE POSTGRESQL DATA VOLUME ==="

        if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
            owner="$(docker volume inspect \
                --format "{{index .Labels \"$LABEL\"}}" \
                "$VOLUME")"

            if [[ "$owner" != "true" ]]; then
                echo "ERROR: Existing volume is not managed by this kit."
                exit 1
            fi

            echo "DATABASE VOLUME: ALREADY PREPARED"
        else
            docker volume create \
                --label "$LABEL=true" \
                "$VOLUME" >/dev/null

            echo "DATABASE VOLUME: CREATED"
        fi

        mkdir -p \
            "$TARGET/runtime/emqx/data" \
            "$TARGET/runtime/kafka/data" \
            "$TARGET/runtime/thingsboard/install-data" \
            "$TARGET/logs/emqx" \
            "$TARGET/logs/kafka"

        echo
        echo "OFFLINE DOCKER RESOURCES: READY"
        echo "Services: NOT STARTED"
        ;;

    *)
        echo "Usage:"
        echo "  $0 --self-test"
        echo "  $0 --prepare /path/to/restored-kit"
        exit 1
        ;;
esac
