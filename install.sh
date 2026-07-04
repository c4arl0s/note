#!/usr/bin/env bash

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$INSTALL_DIR/note.sh"
TARGET="/usr/local/bin/note"

if [[ ! -f "$SOURCE" ]]; then
    echo "Error: note.sh not found at $SOURCE" >&2
    exit 1
fi

chmod +x "$SOURCE"

if [[ -e "$TARGET" || -L "$TARGET" ]]; then
    if [[ "$(readlink "$TARGET" 2>/dev/null || true)" == "$SOURCE" ]]; then
        echo "Already installed: $TARGET -> $SOURCE"
        exit 0
    fi

    echo "Error: $TARGET already exists" >&2
    exit 1
fi

if [[ ! -d "/usr/local/bin" ]]; then
    echo "Creating /usr/local/bin..."
    sudo mkdir -p /usr/local/bin
fi

sudo ln -s "$SOURCE" "$TARGET"
echo "Installed: $TARGET -> $SOURCE"
