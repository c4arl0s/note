#!/usr/bin/env bash

DIALOG="/opt/homebrew/bin/dialog"
FZY="/opt/homebrew/bin/fzy"
NOTES_FILE="${NOTES_FILE:-$HOME/notes.txt}"

usage() {
    cat >&2 <<EOF
Usage:
  $(basename "$0") -a "<title>"   Add a note
  $(basename "$0") -l             List and search notes
  $(basename "$0") "<title>"      Add a note (shortcut)
EOF
}

check_dependencies() {
    if [[ ! -x "$DIALOG" ]]; then
        echo "Error: dialog not found at $DIALOG" >&2
        exit 1
    fi
}

add_note() {
    if [[ $# -lt 1 ]]; then
        echo "Error: title is required" >&2
        usage
        exit 1
    fi

    local title="$*"
    local temp_in
    temp_in=$(mktemp)
    : > "$temp_in"

    local note
    if ! note=$("$DIALOG" --stdout \
        --title "$title" \
        --ok-label "Save" \
        --cancel-label "Cancel" \
        --editbox "$temp_in" 20 60); then
        rm -f "$temp_in"
        return 0
    fi

    rm -f "$temp_in"

    note="${note//$'\r'/}"
    note="${note//$'\n'/ }"
    note="${note#"${note%%[![:space:]]*}"}"
    note="${note%"${note##*[![:space:]]}"}"

    if [[ -z "$note" ]]; then
        return 0
    fi

    printf '%s : (%s)\n' "$(date '+%Y-%m-%d %H:%M')" "$note" >> "$NOTES_FILE"
}

list_notes() {
    if [[ ! -x "$FZY" ]]; then
        echo "Error: fzy not found at $FZY" >&2
        exit 1
    fi

    if [[ ! -s "$NOTES_FILE" ]]; then
        "$DIALOG" --title "Notes" --msgbox "No notes found." 8 40
        return 0
    fi

    local selected
    selected=$(<"$NOTES_FILE" "$FZY") || return 0

    if [[ -z "$selected" ]]; then
        return 0
    fi

    local temp_display
    temp_display=$(mktemp)
    printf '%s\n' "$selected" > "$temp_display"

    "$DIALOG" --title "Note" --textbox "$temp_display" 20 70
    rm -f "$temp_display"
}

check_dependencies

case "${1:-}" in
    -a|--add)
        shift
        add_note "$@"
        ;;
    -l|--list)
        list_notes
        ;;
    -h|--help)
        usage
        ;;
    "")
        usage
        exit 1
        ;;
    *)
        add_note "$@"
        ;;
esac
