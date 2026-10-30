#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS="$KIT_ROOT/offline-bundle/dependencies"

names=(maven gradle yarn pnpm pip emqx)

verify_archives() {
    echo "=== VERIFY DEPENDENCY ARCHIVES ==="

    for name in "${names[@]}"; do
        if [[ ! -f "$DEPS/${name}-cache.tar.gz" ]]; then
            echo "ERROR: Missing ${name}-cache.tar.gz"
            exit 1
        fi
    done

    (
        cd "$KIT_ROOT"
        sha256sum -c \
          offline-bundle/dependencies/SHA256SUMS
    )

    echo "DEPENDENCY ARCHIVES: VERIFIED"
}

if [[ "${1:-}" == "--verify" && $# -eq 1 ]]; then
    verify_archives
    exit 0
fi

if [[ $# -ne 1 ]]; then
    echo "Usage:"
    echo "  $0 --verify"
    echo "  $0 /path/to/restored-kit"
    exit 1
fi

TARGET="$(realpath -m -- "$1")"

case "$TARGET" in
    "$KIT_ROOT"|"$KIT_ROOT"/*)
        echo "ERROR: Destination must be outside the original kit."
        exit 1
        ;;
esac

if [[ -e "$TARGET/caches" || -L "$TARGET/caches" ]]; then
    echo "ERROR: Destination caches directory already exists."
    echo "Existing cache files will not be overwritten."
    exit 1
fi

verify_archives

mkdir -p "$TARGET"

STAGING="$(mktemp -d "$TARGET/.caches-restore.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT

echo
echo "=== RESTORING OFFLINE DEPENDENCIES ==="

for name in "${names[@]}"; do
    echo "Restoring $name..."

    tar -xzf "$DEPS/${name}-cache.tar.gz" \
        -C "$STAGING"

    if [[ ! -d "$STAGING/$name" ]]; then
        echo "ERROR: $name cache was not restored."
        exit 1
    fi

    echo "$name CACHE RESTORE: PASS"
done

mv -- "$STAGING" "$TARGET/caches"
trap - EXIT

echo
echo "=== RESTORED CACHE SIZE ==="
du -sh "$TARGET/caches"

echo
echo "OFFLINE DEPENDENCY RESTORATION: PASS"
echo "Destination: $TARGET/caches"
