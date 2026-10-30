#!/usr/bin/env bash
set -euo pipefail
umask 077

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VOLUME="iot-postgres-data"
IMAGE="postgres:17"

verify_backup() {
    local backup="$1"

    if [[ ! -s "$backup" ]]; then
        echo "ERROR: Backup file is missing or empty."
        exit 1
    fi

    docker image inspect "$IMAGE" >/dev/null

    if [[ -f "${backup}.sha256" ]]; then
        local expected actual

        expected="$(awk 'NR==1 {print $1}' "${backup}.sha256")"
        actual="$(sha256sum "$backup" | awk '{print $1}')"

        if [[ "$expected" != "$actual" ]]; then
            echo "ERROR: Backup checksum mismatch."
            exit 1
        fi

        echo "POSTGRESQL BACKUP CHECKSUM: PASS"
    else
        echo "NOTE: No separate checksum file found."
    fi

    docker run --rm \
        --network none \
        --pull=never \
        -i \
        --entrypoint pg_restore \
        "$IMAGE" \
        --list < "$backup" >/dev/null

    echo "POSTGRESQL BACKUP ARCHIVE: PASS"
}

case "${1:-}" in

    --verify-backup)
        [[ $# -eq 2 ]] || exit 1
        verify_backup "$2"
        echo "OFFLINE POSTGRESQL BACKUP VERIFICATION: PASS"
        ;;

    --restore)
        if [[ $# -ne 3 ]]; then
            echo "Usage: $0 --restore /path/to/restored-kit /path/to/backup.dump"
            exit 1
        fi

        TARGET="$(realpath -m -- "$2")"
        BACKUP="$(realpath -e -- "$3")"

        case "$TARGET" in
            "$KIT_ROOT"|"$KIT_ROOT"/*)
                echo "ERROR: Cannot restore into the original kit."
                exit 1
                ;;
        esac

        if [[ ! -f "$TARGET/compose.yaml" ||
              ! -f "$TARGET/runtime/postgres/postgres.env" ]]; then
            echo "ERROR: Restored PostgreSQL configuration is missing."
            exit 1
        fi

        if docker container inspect iot-postgres >/dev/null 2>&1; then
            echo "ERROR: iot-postgres container already exists."
            exit 1
        fi

        if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
            echo "ERROR: PostgreSQL volume is not prepared."
            exit 1
        fi

        owner="$(docker volume inspect \
            --format '{{index .Labels "offline.iot-kit.managed"}}' \
            "$VOLUME")"

        if [[ "$owner" != "true" ]]; then
            echo "ERROR: PostgreSQL volume is not managed by this kit."
            exit 1
        fi

        if [[ -n "$(docker ps -aq --filter "volume=$VOLUME")" ]]; then
            echo "ERROR: Existing containers reference the database volume."
            exit 1
        fi

        verify_backup "$BACKUP"

        echo "=== CHECK DATABASE VOLUME IS EMPTY ==="

        docker run --rm \
            --network none \
            --pull=never \
            --mount "type=volume,source=$VOLUME,target=/volume,readonly,volume-nocopy" \
            --entrypoint /bin/sh \
            "$IMAGE" \
            -ec 'test -z "$(find /volume -mindepth 1 -print -quit)"' || {
                echo "ERROR: Database volume is not empty."
                echo "Existing database files will not be overwritten."
                exit 1
            }

        echo "EMPTY DATABASE VOLUME: VERIFIED"

        container="iot-pg-offline-restore-$$"

        cleanup() {
            docker rm -f "$container" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT

        echo "=== START ISOLATED POSTGRESQL CONTAINER ==="

        docker run -d \
            --rm \
            --network none \
            --pull=never \
            --name "$container" \
            --env-file "$TARGET/runtime/postgres/postgres.env" \
            --mount "type=volume,source=$VOLUME,target=/var/lib/postgresql/data,volume-nocopy" \
            "$IMAGE" >/dev/null

        ready=0

        for attempt in $(seq 1 60); do
            if docker exec "$container" sh -ec \
                'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
                >/dev/null 2>&1; then
                ready=1
                break
            fi
            sleep 1
        done

        if [[ "$ready" -ne 1 ]]; then
            echo "ERROR: PostgreSQL did not become ready."
            exit 1
        fi

        echo "POSTGRESQL DATABASE: READY"

        echo "=== RESTORE PRIVATE DATABASE BACKUP ==="

        docker exec -i "$container" sh -ec '
            export PGPASSWORD="$POSTGRES_PASSWORD"
            exec pg_restore \
                --format=custom \
                --no-owner \
                --no-acl \
                --exit-on-error \
                --username="$POSTGRES_USER" \
                --dbname="$POSTGRES_DB"
        ' < "$BACKUP"

        echo "=== VERIFY RESTORED TABLES ==="

        table_count="$(
            docker exec "$container" sh -ec '
                export PGPASSWORD="$POSTGRES_PASSWORD"
                exec psql \
                    -U "$POSTGRES_USER" \
                    -d "$POSTGRES_DB" \
                    -Atc "SELECT count(*) FROM pg_catalog.pg_tables WHERE schemaname = current_schema();"
            '
        )"

        echo "Restored tables: $table_count"

        if [[ ! "$table_count" =~ ^[0-9]+$ ]] ||
           [[ "$table_count" -eq 0 ]]; then
            echo "ERROR: No restored application tables found."
            exit 1
        fi

        echo "OFFLINE POSTGRESQL DATABASE RESTORATION: PASS"
        echo "Database volume: $VOLUME"
        echo "Temporary restore container: WILL BE REMOVED"
        ;;

    *)
        echo "Usage:"
        echo "  $0 --verify-backup /path/to/backup.dump"
        echo "  $0 --restore /path/to/restored-kit /path/to/backup.dump"
        exit 1
        ;;
esac
