#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCHIVES="$KIT_ROOT/offline-bundle/build-resources"

verify_archives() {
    echo "=== VERIFY BUILD RESOURCE ARCHIVES ==="

    (
        cd "$ARCHIVES"
        sha256sum -c SHA256SUMS
    )

    echo "BUILD RESOURCE ARCHIVES: VERIFIED"
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
        echo "ERROR: Cannot overwrite the original kit."
        exit 1
        ;;
esac

echo "=== CHECK RESTORED SOURCE REPOSITORIES ==="

for project in emqx kafka thingsboard; do
    if [[ ! -d "$TARGET/sources/$project/.git" ]]; then
        echo "ERROR: Missing restored source: $project"
        exit 1
    fi
done

resources=(
    "sources/emqx/deps"
    "sources/emqx/_build"
    "sources/kafka/.gradle"
    "sources/thingsboard/ui-ngx/node_modules"
)

for resource in "${resources[@]}"; do
    if [[ -e "$TARGET/$resource" || -L "$TARGET/$resource" ]]; then
        echo "ERROR: Already exists: $TARGET/$resource"
        exit 1
    fi
done

verify_archives

echo
echo "=== EXTRACT BUILD RESOURCES TO STAGING ==="

STAGING="$(mktemp -d "$TARGET/.build-resources.XXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT

mkdir -p \
    "$STAGING/emqx" \
    "$STAGING/kafka" \
    "$STAGING/thingsboard"

tar -xzf "$ARCHIVES/emqx-build-resources.tar.gz" \
    -C "$STAGING/emqx"

tar -xzf "$ARCHIVES/kafka-gradle-resources.tar.gz" \
    -C "$STAGING/kafka"

tar -xzf "$ARCHIVES/thingsboard-frontend-deps.tar.gz" \
    -C "$STAGING/thingsboard"

echo
echo "=== VERIFY EXTRACTED DIRECTORIES ==="

for resource in \
    "$STAGING/emqx/deps" \
    "$STAGING/emqx/_build" \
    "$STAGING/kafka/.gradle" \
    "$STAGING/thingsboard/node_modules"; do

    if [[ ! -d "$resource" ]]; then
        echo "ERROR: Missing extracted directory: $resource"
        exit 1
    fi
done

echo
echo "=== INSTALL RESTORED BUILD RESOURCES ==="

mv "$STAGING/emqx/deps" \
   "$TARGET/sources/emqx/deps"

mv "$STAGING/emqx/_build" \
   "$TARGET/sources/emqx/_build"

mv "$STAGING/kafka/.gradle" \
   "$TARGET/sources/kafka/.gradle"

mv "$STAGING/thingsboard/node_modules" \
   "$TARGET/sources/thingsboard/ui-ngx/node_modules"

echo "EMQX BUILD RESOURCES: PASS"
echo "KAFKA BUILD RESOURCES: PASS"
echo "THINGSBOARD BUILD RESOURCES: PASS"

echo
echo "OFFLINE BUILD RESOURCE RESTORATION: PASS"
