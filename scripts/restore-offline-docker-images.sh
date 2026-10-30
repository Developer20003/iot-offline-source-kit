#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_DIR="$KIT_ROOT/offline-bundle/docker-images"

archives=(
    postgres-17
    java17-kafka
    maven-thingsboard
    emqx-builder
    node22-zigbee2mqtt
    python312-ble
)

images=(
    "postgres:17"
    "eclipse-temurin:17-jdk"
    "maven:3.9.9-eclipse-temurin-17"
    "ghcr.io/emqx/emqx-builder/6.1-8:1.19.1-28.4.1-4-ubuntu24.04"
    "node:22.22.2-bookworm"
    "python:3.12"
)

verify_images() {
    echo "=== VERIFY DOCKER IMAGE ARCHIVES ==="

    for name in "${archives[@]}"; do
        if [[ ! -f "$IMAGE_DIR/${name}.tar.gz" ]]; then
            echo "ERROR: Missing Docker image archive: $name"
            exit 1
        fi
    done

    (
        cd "$IMAGE_DIR"
        sha256sum -c SHA256SUMS
    )

    echo
    echo "DOCKER IMAGE ARCHIVES: VERIFIED"
}

case "${1:-}" in

    --verify)
        [[ $# -eq 1 ]] || exit 1
        verify_images
        ;;

    --load)
        [[ $# -eq 1 ]] || exit 1

        verify_images

        if ! docker info >/dev/null 2>&1; then
            echo "ERROR: Docker Engine is not available."
            exit 1
        fi

        echo
        echo "=== RESTORE DOCKER IMAGES ==="

        for i in "${!archives[@]}"; do
            archive="$IMAGE_DIR/${archives[$i]}.tar.gz"
            image="${images[$i]}"

            echo
            echo "Loading $image"

            docker image load -i "$archive"

            docker image inspect "$image" >/dev/null

            echo "${archives[$i]} IMAGE RESTORE: PASS"
        done

        echo
        echo "OFFLINE DOCKER IMAGE RESTORATION: PASS"
        ;;

    *)
        echo "Usage:"
        echo "  $0 --verify"
        echo "  $0 --load"
        exit 1
        ;;
esac
