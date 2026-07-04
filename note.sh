#!/usr/bin/env bash

DIALOG="/opt/homebrew/bin/dialog"
NOTES_FILE="${NOTES_FILE:-$HOME/notes.txt}"

if [[ $# -lt 1 ]]; then
    echo "Usage: note \"<title>\"" >&2
    exit 1
fi

if [[ ! -x "$DIALOG" ]]; then
    echo "Error: dialog not found at $DIALOG" >&2
    exit 1
fi

TITLE="$*"
TEMP_IN=$(mktemp)
trap 'rm -f "$TEMP_IN"' EXIT
: > "$TEMP_IN"

# editbox loads TEMP_IN and writes edited content to stdout when using --stdout
if ! NOTE=$("$DIALOG" --stdout \
    --title "$TITLE" \
    --ok-label "Save" \
    --cancel-label "Cancel" \
    --editbox "$TEMP_IN" 20 60); then
    exit 0
fi

NOTE="${NOTE//$'\r'/}"
NOTE="${NOTE//$'\n'/ }"
NOTE="${NOTE#"${NOTE%%[![:space:]]*}"}"
NOTE="${NOTE%"${NOTE##*[![:space:]]}"}"

if [[ -z "$NOTE" ]]; then
    exit 0
fi

printf '%s : (%s)\n' "$(date '+%Y-%m-%d %H:%M')" "$NOTE" >> "$NOTES_FILE"
