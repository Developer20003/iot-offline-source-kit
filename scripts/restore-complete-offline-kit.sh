#!/usr/bin/env bash
set -euo pipefail
umask 077

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

verify_all() {
    echo "=== VERIFY SOURCE BUNDLES ==="
    bash "$KIT_ROOT/scripts/restore-offline-sources.sh" --verify

    echo
    echo "=== VERIFY DEPENDENCY CACHES ==="
    bash "$KIT_ROOT/scripts/restore-offline-caches.sh" --verify

    echo
    echo "=== VERIFY BUILD RESOURCES ==="
    bash "$KIT_ROOT/scripts/restore-offline-build-resources.sh" --verify

    echo
    echo "=== VERIFY COMPILED APPLICATIONS ==="
    bash "$KIT_ROOT/scripts/restore-offline-runtime.sh" --verify

    echo
    echo "=== VERIFY PORTABLE CONFIGURATION ==="
    bash "$KIT_ROOT/scripts/restore-offline-config.sh" --verify

    echo
    echo "=== VERIFY DOCKER IMAGE ARCHIVES ==="
    bash "$KIT_ROOT/scripts/restore-offline-docker-images.sh" --verify

    echo
    echo "COMPLETE OFFLINE PACKAGE VERIFICATION: PASS"
}

case "${1:-}" in
    --verify)
        if [ $# -ne 1 ]; then
            echo "Usage: $0 --verify"
            exit 1
        fi

        verify_all
        ;;

    --restore)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 --restore /path/to/new-kit"
            exit 1
        fi

        command -v git >/dev/null
        command -v python3 >/dev/null
        command -v tar >/dev/null
        command -v sha256sum >/dev/null

        TARGET="$(realpath -m -- "$2")"

        case "$TARGET" in
            "$KIT_ROOT"|"$KIT_ROOT"/*)
                echo "ERROR: Cannot overwrite the original kit."
                exit 1
                ;;
        esac

        if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
            echo "ERROR: Destination already exists."
            echo "Choose a new directory."
            exit 1
        fi

        verify_all

        echo
        echo "=== 1. RESTORE SOURCE CODE ==="
        bash "$KIT_ROOT/scripts/restore-offline-sources.sh" \
            "$TARGET"

        echo
        echo "=== 2. RESTORE DEPENDENCY CACHES ==="
        bash "$KIT_ROOT/scripts/restore-offline-caches.sh" \
            "$TARGET"

        echo
        echo "=== 3. RESTORE BUILD RESOURCES ==="
        bash "$KIT_ROOT/scripts/restore-offline-build-resources.sh" \
            --restore "$TARGET"

        echo
        echo "=== 4. RESTORE COMPILED APPLICATIONS ==="
        bash "$KIT_ROOT/scripts/restore-offline-runtime.sh" \
            --restore "$TARGET"

        echo
        echo "=== 5. RESTORE SERVICE CONFIGURATION ==="
        bash "$KIT_ROOT/scripts/restore-offline-config.sh" \
            --restore "$TARGET"

        echo
        echo "=== 6. GENERATE PRIVATE CREDENTIALS ==="
        bash "$KIT_ROOT/scripts/init-offline-instance.sh" \
            "$TARGET"

        echo
        echo "=== 7. RESTORE INSTALLATION SCRIPTS ==="

        if [[ -e "$TARGET/scripts" || -L "$TARGET/scripts" ]]; then
            echo "ERROR: Installation scripts already exist."
            exit 1
        fi

        (
            cd "$KIT_ROOT/offline-bundle"
            sha256sum -c installer-scripts.tar.gz.sha256
        )

        tar -xzf "$KIT_ROOT/offline-bundle/installer-scripts.tar.gz"             -C "$TARGET"

        count=0

        for script in "$TARGET"/scripts/*.sh; do
            bash -n "$script"
            count=$((count + 1))
        done

        if [[ "$count" -ne 13 ]]; then
            echo "ERROR: Expected 13 restored installation scripts."
            exit 1
        fi

        echo "INSTALLATION SCRIPTS RESTORED: PASS"

        echo
        echo "=== VERIFY RESTORED SOURCE COMMITS ==="

        while read -r project expected; do
            actual="$(
                git -C "$TARGET/sources/$project" rev-parse HEAD
            )"

            if [ "$actual" != "$expected" ]; then
                echo "ERROR: $project commit mismatch."
                exit 1
            fi

            echo "$project SOURCE COMMIT: PASS"
        done < "$KIT_ROOT/offline-bundle/source-commits.txt"

        echo
        echo "COMPLETE OFFLINE FILE RESTORATION: PASS"
        echo "Destination: $TARGET"
        echo "Docker images: NOT YET LOADED"
        echo "Kafka storage: NOT YET INITIALIZED"
        echo "Database: NOT YET RESTORED"
        echo "Containers: NOT STARTED"
        ;;

    *)
        echo "Usage:"
        echo "  $0 --verify"
        echo "  $0 --restore /path/to/new-kit"
        exit 1
        ;;
esac
