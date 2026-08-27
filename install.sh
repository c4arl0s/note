#!/usr/bin/env bash

set -euo pipefail

install_dependency() {
    local name="$1"
    local brew_formula="$2"
    local fallback_path="$3"

    if command -v "$name" >/dev/null 2>&1 || [[ -x "$fallback_path" ]]; then
        echo "Dependency '$name' is already available."
        return 0
    fi

    echo "Installing '$name'..."
    if ! command -v brew >/dev/null 2>&1; then
        echo "Error: Homebrew (brew) is not installed. Please install it first or install '$name' manually." >&2
        exit 1
    fi

    brew install "$brew_formula"
}

echo "Checking dependencies..."
install_dependency "fzy" "fzy" "/opt/homebrew/bin/fzy"
install_dependency "glow" "glow" "/opt/homebrew/bin/glow"
echo "Dependencies OK."


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
