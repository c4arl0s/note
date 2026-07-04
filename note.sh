#!/usr/bin/env bash

FZY="/opt/homebrew/bin/fzy"
NOTES_FILE="${NOTES_FILE:-$HOME/notes.txt}"

NOTE_START="<<<NOTE>>>"
NOTE_END="<<<END>>>"
INPUT_END_MARKER="."

usage() {
    cat >&2 <<EOF
Usage:
  $(basename "$0") -a [options] "<title>"   Add a note
  $(basename "$0") -l                         List and search notes
  $(basename "$0") [options] "<title>"        Add a note (shortcut)

Add options:
  (default)             Interactive input; save with "." or "EOF" on its own line, or Ctrl+D
  -m, --message TEXT   Save TEXT directly without stdin
  -f, --file PATH       Save note content from a file
  -e, --editor           Open \$EDITOR to write the note

Examples:
  $(basename "$0") -a "Meeting notes"
  $(basename "$0") -a -m "Remember to call John" "Reminder"
  $(basename "$0") -a -f ./draft.txt "Meeting notes"
  $(basename "$0") -a -e "Meeting notes"
  cat notes.md | $(basename "$0") -a "Meeting notes"
EOF
}

note_is_empty() {
    local file="$1"
    [[ ! -s "$file" ]] && return 0
    [[ -z "$(tr -d '[:space:]' < "$file" 2>/dev/null)" ]]
}

encode_content() {
    awk 'BEGIN { first = 1 } {
        if (!first) printf "\\n"
        first = 0
        gsub(/\\/, "\\\\")
        printf "%s", $0
    }' "$1"
}

decode_content() {
    local encoded="$1"
    local line rest

    while [[ -n "$encoded" ]]; do
        if [[ "$encoded" == *'\n'* ]]; then
            line="${encoded%%\\n*}"
            rest="${encoded#*\\n}"
        else
            line="$encoded"
            rest=""
        fi
        printf '%s\n' "$line"
        encoded="$rest"
    done
}

save_note() {
    local timestamp="$1"
    local title="$2"
    local content_file="$3"
    local encoded

    encoded=$(encode_content "$content_file")
    printf '%s : %s : (%s)\n' "$timestamp" "$title" "$encoded" >> "$NOTES_FILE"
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

index_single_line_note() {
    local index_dir="$1"
    local summaries_file="$2"
    local idx="$3"
    local timestamp="$4"
    local title="$5"
    local encoded="$6"
    local body_file preview summary

    body_file="$index_dir/$idx.body"
    decode_content "$encoded" > "$body_file"
    preview=$(note_preview "$body_file")
    summary="${timestamp} | ${title} | ${preview}"
    printf '%s\t%s\t%s\t%s\n' "$idx" "$title" "$timestamp" "$summary" >> "$summaries_file"
}

build_note_index() {
    local index_dir="$1"
    local summaries_file="$2"
    local idx=0
    local in_note=0
    local timestamp=""
    local title=""
    local body_file=""
    local line=""
    local encoded=""
    local block_body=""

    : > "$summaries_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == "$NOTE_START" ]]; then
            in_note=1
            idx=$((idx + 1))
            body_file="$index_dir/$idx.body"
            block_body=""
            timestamp="Unknown"
            title="(untitled)"
            IFS= read -r line || line=""

            if [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}$ ]]; then
                timestamp="$line"
                IFS= read -r title || title="(untitled)"
            else
                title="$line"
                IFS= read -r line || line=""
                [[ "$line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}$ ]] && timestamp="$line"
            fi
            continue
        fi

        if [[ "$line" == "$NOTE_END" ]]; then
            if (( in_note )); then
                body_file="$index_dir/$idx.body"
                printf '%s' "$block_body" > "$body_file"
                encoded=$(encode_content "$body_file")
                index_single_line_note "$index_dir" "$summaries_file" "$idx" "$timestamp" "$title" "$encoded"
            fi
            in_note=0
            continue
        fi

        if (( in_note )); then
            if [[ -n "$block_body" ]]; then
                block_body+=$'\n'
            fi
            block_body+="$line"
            continue
        fi

        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2})[[:space:]]*:[[:space:]]*(.+)[[:space:]]*:[[:space:]]*\((.*)\)[[:space:]]*$ ]]; then
            idx=$((idx + 1))
            index_single_line_note "$index_dir" "$summaries_file" "$idx" \
                "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
            continue
        fi

        if [[ "$line" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2})[[:space:]]*:[[:space:]]*\((.*)\)[[:space:]]*$ ]]; then
            idx=$((idx + 1))
            index_single_line_note "$index_dir" "$summaries_file" "$idx" \
                "${BASH_REMATCH[1]}" "(untitled)" "${BASH_REMATCH[2]}"
        fi
    done < "$NOTES_FILE"
}

read_note_interactive() {
    local output_file="$1"
    local line=""

    : > "$output_file"

    cat >&2 <<'EOF'
Enter your note below.

Save with any of these:
  - A line containing only "."
  - A line containing only "EOF"
  - Ctrl+D on an empty line
EOF

    while IFS= read -r line; do
        if [[ "$line" == "$INPUT_END_MARKER" || "$line" == "EOF" ]]; then
            break
        fi
        printf '%s\n' "$line" >> "$output_file"
    done
}

read_note_editor() {
    local output_file="$1"
    local temp_file editor

    temp_file=$(mktemp)
    : > "$temp_file"
    editor="${EDITOR:-nano}"

    if ! command -v "$editor" >/dev/null 2>&1; then
        editor="vi"
    fi

    "$editor" "$temp_file"
    cp "$temp_file" "$output_file"
    rm -f "$temp_file"
}

read_note_from_file() {
    local source_file="$1"
    local output_file="$2"

    if [[ ! -f "$source_file" ]]; then
        echo "Error: file not found: $source_file" >&2
        exit 1
    fi

    cp "$source_file" "$output_file"
}

read_note_from_stdin() {
    local output_file="$1"

    if [[ -t 0 ]]; then
        read_note_interactive "$output_file"
    else
        cat > "$output_file"
    fi
}

add_note() {
    local mode="interactive"
    local source_file=""
    local message=""
    local title=""
    local temp_out

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--editor)
                mode="editor"
                shift
                ;;
            -f|--file)
                mode="file"
                source_file="$2"
                shift 2
                ;;
            -m|--message)
                mode="message"
                message="$2"
                shift 2
                ;;
            -h|--help)
                usage
                return 0
                ;;
            -*)
                echo "Error: unknown option: $1" >&2
                usage
                exit 1
                ;;
            *)
                title="$*"
                break
                ;;
        esac
    done

    if [[ -z "$title" ]]; then
        echo "Error: title is required" >&2
        usage
        exit 1
    fi

    temp_out=$(mktemp)

    case "$mode" in
        editor)
            read_note_editor "$temp_out"
            ;;
        file)
            read_note_from_file "$source_file" "$temp_out"
            ;;
        message)
            printf '%s' "$message" > "$temp_out"
            ;;
        interactive)
            read_note_from_stdin "$temp_out"
            ;;
    esac

    if note_is_empty "$temp_out"; then
        rm -f "$temp_out"
        echo "Note not saved (empty content)." >&2
        return 0
    fi

    save_note "$(date '+%Y-%m-%d %H:%M')" "$title" "$temp_out"
    rm -f "$temp_out"
    echo "Note saved." >&2
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

    printf 'Date: %s\n' "$timestamp"
    printf 'Title: %s\n\n' "$title"
    cat "$body_file"

    rm -rf "$index_dir" "$summaries_file" "$fzy_input"
}

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
