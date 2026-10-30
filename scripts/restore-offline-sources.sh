#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$KIT_ROOT/offline-bundle"
MANIFEST="$BUNDLE/source-commits.txt"

verify_bundles() {
    echo "=== VERIFY OFFLINE SOURCE BUNDLES ==="
    (
        cd "$BUNDLE/git"
        sha256sum -c SHA256SUMS
    )
}

if [[ "${1:-}" == "--verify" ]]; then
    verify_bundles
    echo "OFFLINE SOURCE BUNDLES: VERIFIED"
    exit 0
fi

if [[ $# -ne 1 ]]; then
    echo "Usage:"
    echo "  $0 --verify"
    echo "  $0 /path/to/new/empty/directory"
    exit 1
fi

TARGET="$(realpath -m "$1")"

# Never restore over the existing development kit.
case "$TARGET" in
    "$KIT_ROOT"|"$KIT_ROOT"/*)
        echo "ERROR: Restore destination must be outside the original kit."
        exit 1
        ;;
esac

if [[ -e "$TARGET" ]]; then
    echo "ERROR: Destination already exists: $TARGET"
    echo "Choose a new directory to protect existing files."
    exit 1
fi

verify_bundles

if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: Missing source commit manifest."
    exit 1
fi

mkdir -p "$TARGET/sources"

echo
echo "=== RESTORING SOURCE REPOSITORIES ==="

while read -r project commit; do
    case "$project" in
        emqx|kafka|thingsboard|zigbee2mqtt) ;;
        *)
            echo "ERROR: Unexpected project: $project"
            exit 1
            ;;
    esac

    echo
    echo "Restoring $project..."

    GIT_LFS_SKIP_SMUDGE=1 git clone \
        --quiet \
        --no-checkout \
        "$BUNDLE/git/$project.bundle" \
        "$TARGET/sources/$project"

    GIT_LFS_SKIP_SMUDGE=1 git -C "$TARGET/sources/$project" \
        checkout --quiet --detach "$commit"

    restored="$(git -C "$TARGET/sources/$project" rev-parse HEAD)"

    if [[ "$restored" != "$commit" ]]; then
        echo "ERROR: $project commit mismatch"
        exit 1
    fi

    echo "$project SOURCE RESTORE: PASS"
done < "$MANIFEST"

echo
echo "OFFLINE SOURCE RESTORATION: PASS"
echo "Destination: $TARGET"
