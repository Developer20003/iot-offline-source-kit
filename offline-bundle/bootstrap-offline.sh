#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/offline-bundle"
ARCHIVE="$BUNDLE/installer-scripts.tar.gz"

verify() {
    echo "=== VERIFY OFFLINE INSTALLER ==="

    (
        cd "$BUNDLE"
        sha256sum -c installer-scripts.tar.gz.sha256
    )

    mapfile -t files < <(tar -tzf "$ARCHIVE")

    if [[ "${#files[@]}" -ne 13 ]]; then
        echo "ERROR: Expected 13 installation scripts."
        exit 1
    fi

    for file in "${files[@]}"; do
        if [[ ! "$file" =~ ^scripts/[a-zA-Z0-9-]+\.sh$ ]]; then
            echo "ERROR: Unexpected archive path: $file"
            exit 1
        fi
    done

    echo "INSTALLER CONTENTS: VERIFIED"
}

case "${1:-}" in
    --verify)
        [[ $# -eq 1 ]] || exit 1
        verify
        echo "OFFLINE BOOTSTRAP VERIFICATION: PASS"
        ;;

    --extract)
        [[ $# -eq 1 ]] || exit 1

        if [[ -e "$ROOT/scripts" || -L "$ROOT/scripts" ]]; then
            echo "ERROR: scripts directory already exists."
            echo "Existing scripts will not be overwritten."
            exit 1
        fi

        verify

        echo "=== EXTRACT OFFLINE INSTALLATION SCRIPTS ==="

        tar -xzf "$ARCHIVE" -C "$ROOT"

        count=0
        for file in "$ROOT"/scripts/*.sh; do
            bash -n "$file"
            count=$((count + 1))
        done

        [[ "$count" -eq 13 ]]

        echo "EXTRACTED INSTALLATION SCRIPTS: 13/13 PASS"
        echo "OFFLINE BOOTSTRAP EXTRACTION: PASS"
        ;;

    *)
        echo "Usage:"
        echo "  $0 --verify"
        echo "  $0 --extract"
        exit 1
        ;;
esac
