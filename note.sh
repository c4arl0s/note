#!/usr/bin/env bash

DIALOG="/opt/homebrew/bin/dialog"
FZY="/opt/homebrew/bin/fzy"
NOTES_FILE="${NOTES_FILE:-$HOME/notes.txt}"

NOTE_START="<<<NOTE>>>"
NOTE_END="<<<END>>>"

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

dialog_size() {
    local height width
    height=$(tput lines 2>/dev/null || echo 24)
    width=$(tput cols 2>/dev/null || echo 80)
    height=${height//[^0-9]/}
    width=${width//[^0-9]/}
    [[ -z "$height" ]] && height=24
    [[ -z "$width" ]] && width=80
    height=$((height - 3))
    width=$((width - 6))
    (( height < 12 )) && height=12
    (( width < 50 )) && width=50
    echo "$height $width"
}

note_is_empty() {
    local file="$1"
    [[ ! -s "$file" ]] && return 0
    [[ -z "$(tr -d '[:space:]' < "$file" 2>/dev/null)" ]]
}

save_note() {
    local title="$1"
    local timestamp="$2"
    local content_file="$3"

    {
        printf '%s\n' "$NOTE_START"
        printf '%s\n' "$title"
        printf '%s\n' "$timestamp"
        cat "$content_file"
        printf '%s\n' "$NOTE_END"
    } >> "$NOTES_FILE"
}

note_preview() {
    local body_file="$1"
    local line=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "$line" ]]; then
            printf '%s' "$line"
            return 0
        fi
    done < "$body_file"

    printf '(empty note)'
}

build_note_index() {
    local index_dir="$1"
    local summaries_file="$2"
    local idx=0
    local in_note=0
    local title=""
    local timestamp=""
    local body_file=""
    local line=""
    local preview=""
    local summary=""

    : > "$summaries_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$NOTE_START" ]]; then
            in_note=1
            idx=$((idx + 1))
            body_file="$index_dir/$idx.body"
            : > "$body_file"
            title=""
            timestamp="Unknown"

            IFS= read -r line || line=""
            if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}$ ]]; then
                title="(untitled)"
                timestamp="$line"
            else
                title="$line"
                IFS= read -r timestamp || timestamp="Unknown"
            fi
            continue
        fi

        if [[ "$line" == "$NOTE_END" ]]; then
            if (( in_note )) && [[ -n "$body_file" ]]; then
                preview=$(note_preview "$body_file")
                summary="${title} | ${timestamp} | ${preview}"
                printf '%s\t%s\t%s\t%s\n' "$idx" "$title" "$timestamp" "$summary" >> "$summaries_file"
            fi
            in_note=0
            body_file=""
            continue
        fi

        if (( in_note )) && [[ -n "$body_file" ]]; then
            printf '%s\n' "$line" >> "$body_file"
            continue
        fi

        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2})[[:space:]]*:[[:space:]]*\((.*)\)[[:space:]]*$ ]]; then
            idx=$((idx + 1))
            title="(untitled)"
            timestamp="${BASH_REMATCH[1]}"
            body_file="$index_dir/$idx.body"
            printf '%s' "${BASH_REMATCH[2]}" > "$body_file"
            preview=$(note_preview "$body_file")
            summary="${title} | ${timestamp} | ${preview}"
            printf '%s\t%s\t%s\t%s\n' "$idx" "$title" "$timestamp" "$summary" >> "$summaries_file"
            body_file=""
        fi
    done < "$NOTES_FILE"
}

add_note() {
    if [[ $# -lt 1 ]]; then
        echo "Error: title is required" >&2
        usage
        exit 1
    fi

    local title="$*"
    local box_height box_width temp_in temp_out
    read -r box_height box_width < <(dialog_size)
    temp_in=$(mktemp)
    temp_out=$(mktemp)
    : > "$temp_in"

    if ! "$DIALOG" \
        --title "$title" \
        --ok-label "Save" \
        --cancel-label "Cancel" \
        --editbox "$temp_in" "$box_height" "$box_width" 2> "$temp_out"; then
        rm -f "$temp_in" "$temp_out"
        return 0
    fi

    if note_is_empty "$temp_out"; then
        rm -f "$temp_in" "$temp_out"
        return 0
    fi

    save_note "$title" "$(date '+%Y-%m-%d %H:%M')" "$temp_out"
    rm -f "$temp_in" "$temp_out"
}

list_notes() {
    if [[ ! -x "$FZY" ]]; then
        echo "Error: fzy not found at $FZY" >&2
        exit 1
    fi

    if [[ ! -s "$NOTES_FILE" ]]; then
        echo "No notes found." >&2
        return 0
    fi

    local index_dir summaries_file fzy_input selected_line note_id title timestamp body_file

    index_dir=$(mktemp -d)
    summaries_file=$(mktemp)
    fzy_input=$(mktemp)

    build_note_index "$index_dir" "$summaries_file"

    if [[ ! -s "$summaries_file" ]]; then
        rm -rf "$index_dir" "$summaries_file" "$fzy_input"
        echo "No notes found." >&2
        return 0
    fi

    awk -F '\t' '{ print $4 }' "$summaries_file" > "$fzy_input"

    selected_line=$(<"$fzy_input" "$FZY") || {
        rm -rf "$index_dir" "$summaries_file" "$fzy_input"
        return 0
    }

    if [[ -z "$selected_line" ]]; then
        rm -rf "$index_dir" "$summaries_file" "$fzy_input"
        return 0
    fi

    note_id=$(awk -F '\t' -v selected="$selected_line" '$4 == selected { print $1; exit }' "$summaries_file")
    title=$(awk -F '\t' -v selected="$selected_line" '$4 == selected { print $2; exit }' "$summaries_file")
    timestamp=$(awk -F '\t' -v selected="$selected_line" '$4 == selected { print $3; exit }' "$summaries_file")
    body_file="$index_dir/$note_id.body"

    if [[ -z "$note_id" || ! -f "$body_file" ]]; then
        rm -rf "$index_dir" "$summaries_file" "$fzy_input"
        return 0
    fi

    printf 'Title: %s\n' "$title"
    printf 'Date: %s\n\n' "$timestamp"
    cat "$body_file"

    rm -rf "$index_dir" "$summaries_file" "$fzy_input"
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
