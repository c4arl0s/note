#!/usr/bin/env bash

FZY="${FZY:-/opt/homebrew/bin/fzy}"
GLOW="${GLOW:-/opt/homebrew/bin/glow}"
NOTES_DIR="${NOTES_DIR:-$HOME/notes}"
NOTES_FILE="${NOTES_FILE:-$HOME/notes.txt}"
export NO_HYPERLINKS="${NO_HYPERLINKS:-1}"

SOURCE_PATH="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE_PATH" ]]; do
    DIR_PATH="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"
    SOURCE_PATH="$(readlink "$SOURCE_PATH")"
    [[ "$SOURCE_PATH" != /* ]] && SOURCE_PATH="$DIR_PATH/$SOURCE_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE_PATH")" && pwd)"

GLOW_THEME_FILE="${GLOW_THEME_FILE:-$SCRIPT_DIR/glow-theme.json}"
GLOW_STYLE_FLAG=""
if [[ -f "$GLOW_THEME_FILE" ]]; then
    GLOW_STYLE_FLAG="--style=$GLOW_THEME_FILE"
fi


NOTE_START="<<<NOTE>>>"
NOTE_END="<<<END>>>"
INPUT_END_MARKER="."

usage() {
    cat >&2 <<EOF
Usage:
  $(basename "$0")                            List and search notes
  $(basename "$0") -a [options] "<title>"   Add a note
  $(basename "$0") [options] "<title>"        Add a note (shortcut)
  $(basename "$0") -D                         Delete a note interactively

Add options:
  (default)             Interactive input; save with "." or "EOF" on its own line, or Ctrl+D
  -m, --message TEXT   Save TEXT directly without stdin
  -f, --file PATH       Save note content from a file
  -e, --editor           Open \$EDITOR to write the note

Examples:
  $(basename "$0")
  $(basename "$0") -a "Meeting notes"
  $(basename "$0") -a -m "Remember to call John" "Reminder"
  $(basename "$0") -a -f ./draft.txt "Meeting notes"
  $(basename "$0") -a -e "Meeting notes"
  cat notes.md | $(basename "$0") -a "Meeting notes"
  $(basename "$0") -D
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
    encoded="$encoded" awk 'BEGIN {
        encoded = ENVIRON["encoded"]
        n = length(encoded)
        result = ""
        for (i = 1; i <= n; i++) {
            char = substr(encoded, i, 1)
            if (char == "\\") {
                if (i < n) {
                    next_char = substr(encoded, i+1, 1)
                    if (next_char == "n") {
                        result = result "\n"
                        i++
                    } else if (next_char == "\\") {
                        result = result "\\"
                        i++
                    } else {
                        result = result char next_char
                        i++
                    }
                } else {
                    result = result "\\"
                }
            } else {
                result = result char
            }
        }
        printf "%s\n", result
    }'
}

generate_note_filename() {
    local title="$1"
    local timestamp="$2"
    local clean_title

    # Convert to lowercase, replace non-alphanumeric with hyphens
    clean_title=$(echo "$title" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
    # Trim leading and trailing hyphens
    clean_title="${clean_title#-}"
    clean_title="${clean_title%-}"

    if [[ -z "$clean_title" || "$clean_title" == "untitled" ]]; then
        # Fallback to date-time format: YYYY-MM-DD-HH-MM
        local clean_ts
        clean_ts=$(echo "$timestamp" | tr -cs '0-9' '-')
        clean_ts="${clean_ts#-}"
        clean_ts="${clean_ts%-}"
        echo "${clean_ts}.txt"
    else
        echo "${clean_title}.txt"
    fi
}

get_unique_filename() {
    local dir="$1"
    local base_name="$2"
    local ext="$3"
    local target="${dir}/${base_name}${ext}"
    local counter=1
    while [[ -f "$target" ]]; do
        target="${dir}/${base_name}-${counter}${ext}"
        counter=$((counter + 1))
    done
    echo "$target"
}

parse_note_file_fast() {
    local filepath="$1"
    local date_val=""
    local title_val=""
    local preview=""
    local line
    local count=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        count=$((count + 1))
        if [[ "$line" =~ ^[Dd]ate:[[:space:]]*(.*)$ ]]; then
            date_val="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^[Tt]itle:[[:space:]]*(.*)$ ]]; then
            title_val="${BASH_REMATCH[1]}"
        elif [[ -n "$line" && ! "$line" =~ ^[Dd]ate: && ! "$line" =~ ^[Tt]itle: ]]; then
            if [[ -z "$preview" ]]; then
                preview="$line"
            fi
        fi
        [[ "$count" -ge 5 ]] && break
    done < "$filepath"

    if [[ -z "$date_val" ]]; then
        date_val=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$filepath" 2>/dev/null || date -r "$filepath" "+%Y-%m-%d %H:%M" 2>/dev/null)
    fi
    if [[ -z "$title_val" ]]; then
        local base
        base=$(basename "$filepath")
        title_val="${base%.txt}"
    fi
    [[ -z "$preview" ]] && preview="(empty note)"

    local summary="${date_val} | ${title_val} | ${preview}"
    printf '%s\t%s\t%s\t%s\n' "$filepath" "$title_val" "$date_val" "$summary"
}

save_note() {
    local timestamp="$1"
    local title="$2"
    local content_file="$3"
    local filename filepath

    mkdir -p "$NOTES_DIR"
    filename=$(generate_note_filename "$title" "$timestamp")
    filepath=$(get_unique_filename "$NOTES_DIR" "${filename%.txt}" ".txt")

    printf 'Date: %s\n' "$timestamp" > "$filepath"
    printf 'Title: %s\n\n' "$title" >> "$filepath"
    cat "$content_file" >> "$filepath"
}

migrate_old_notes() {
    local old_file="$1"
    local target_dir="$2"

    if [[ -f "$old_file" && -s "$old_file" ]]; then
        echo "Migrating old notes from $old_file to $target_dir..." >&2

        local index_dir summaries_file
        index_dir=$(mktemp -d)
        summaries_file=$(mktemp)

        local orig_notes_file="$NOTES_FILE"
        NOTES_FILE="$old_file"
        build_note_index "$index_dir" "$summaries_file"
        NOTES_FILE="$orig_notes_file"

        if [[ -s "$summaries_file" ]]; then
            mkdir -p "$target_dir"
            local idx title timestamp summary body_file filename filepath
            while IFS=$'\t' read -r idx title timestamp summary; do
                body_file="${index_dir}/${idx}.body"
                if [[ -f "$body_file" ]]; then
                    filename=$(generate_note_filename "$title" "$timestamp")
                    filepath=$(get_unique_filename "$target_dir" "${filename%.txt}" ".txt")

                    printf 'Date: %s\n' "$timestamp" > "$filepath"
                    printf 'Title: %s\n\n' "$title" >> "$filepath"
                    cat "$body_file" >> "$filepath"
                fi
            done < "$summaries_file"
        fi

        rm -rf "$index_dir" "$summaries_file"
        mv "$old_file" "${old_file}.bak"
        echo "Migration complete. Old notes archived as ${old_file}.bak" >&2
    fi
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

hyperlink_urls() {
    local reset_color="${1:-\x1b[0m}"
    sed -E 's|(https?://[^]'"'"'`()<>[:space:]]*[^]'"'"'`()<>[:space:].,;:!?])|\x1b[4;34m\1\x1b[0m'"$reset_color"'|g' "${@:2}"
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
    local temp_file editor
    temp_file=$(mktemp)
    : > "$temp_file"

    editor="vim"
    if ! command -v "$editor" >/dev/null 2>&1; then
        editor="vi"
    fi

    "$editor" "$temp_file"
    cp "$temp_file" "$output_file"
    rm -f "$temp_file"

    if [[ -f "$output_file" ]]; then
        if [[ -x "$GLOW" ]]; then
            "$GLOW" ${GLOW_STYLE_FLAG:+"$GLOW_STYLE_FLAG"} "$output_file" 2>/dev/null >&2
        else
            printf '\x1b[37m' >&2
            hyperlink_urls '\x1b[37m' "$output_file" >&2
            printf '\x1b[0m' >&2
        fi
    fi

    return 0
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

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M')"
    save_note "$timestamp" "$title" "$temp_out"
    echo "Note saved." >&2
    if [[ -x "$GLOW" ]]; then
        (
            echo "## ${title}"
            echo "*Date: ${timestamp}*"
            echo "---"
            cat "$temp_out"
        ) | "$GLOW" ${GLOW_STYLE_FLAG:+"$GLOW_STYLE_FLAG"} - 2>/dev/null >&2
    else
        printf '\x1b[36mDate: %s\x1b[0m\n' "$timestamp" >&2
        printf '\x1b[36mTitle: %s\x1b[0m\n\n' "$title" | hyperlink_urls '\x1b[36m' >&2
        printf '\x1b[37m' >&2
        hyperlink_urls '\x1b[37m' "$temp_out" >&2
        printf '\x1b[0m' >&2
    fi
    rm -f "$temp_out"
}

list_notes() {
    local mode="${1:-list}"
    if [[ ! -x "$FZY" ]]; then
        echo "Error: fzy not found at $FZY" >&2
        exit 1
    fi

    if [[ ! -d "$NOTES_DIR" ]] || [[ -z "$(ls -A "$NOTES_DIR" 2>/dev/null)" ]]; then
        echo "No notes found." >&2
        return 0
    fi

    local summaries_file fzy_input selected_line note_path title timestamp body_file
    summaries_file=$(mktemp)
    fzy_input=$(mktemp)

    for file in "$NOTES_DIR"/*.txt; do
        if [[ -f "$file" ]]; then
            parse_note_file_fast "$file" >> "$summaries_file"
        fi
    done

    if [[ ! -s "$summaries_file" ]]; then
        rm -f "$summaries_file" "$fzy_input"
        echo "No notes found." >&2
        return 0
    fi

    # Display newest first
    sort -t $'\t' -k 3,3 -r "$summaries_file" | awk -F '\t' '{ print $4 }' > "$fzy_input"

    selected_line=$(<"$fzy_input" "$FZY") || {
        rm -f "$summaries_file" "$fzy_input"
        return 0
    }

    if [[ -z "$selected_line" ]]; then
        rm -f "$summaries_file" "$fzy_input"
        return 0
    fi

    IFS=$'\t' read -r note_path title timestamp < <(
        selected="$selected_line" awk -F '\t' '
            BEGIN { OFS="\t" }
            $4 == ENVIRON["selected"] { note_path = $1; title = $2; timestamp = $3 }
            END { if (note_path != "") print note_path, title, timestamp }
        ' "$summaries_file"
    )

    if [[ -z "$note_path" || ! -f "$note_path" ]]; then
        rm -f "$summaries_file" "$fzy_input"
        return 0
    fi

    # Extract note body (skipping headers)
    body_file=$(mktemp)
    local in_body=0
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$in_body" -eq 0 ]]; then
            if [[ -z "$line" ]]; then
                in_body=1
            fi
        else
            printf '%s\n' "$line" >> "$body_file"
        fi
    done < "$note_path"

    if [[ -x "$GLOW" ]]; then
        (
            echo "## ${title}"
            echo "*Date: ${timestamp}*"
            echo "---"
            cat "$body_file"
        ) | "$GLOW" ${GLOW_STYLE_FLAG:+"$GLOW_STYLE_FLAG"} - 2>/dev/null
    else
        printf '\x1b[36mDate: %s\x1b[0m\n' "$timestamp"
        printf '\x1b[36mTitle: %s\x1b[0m\n\n' "$title" | hyperlink_urls '\x1b[36m'
        printf '\x1b[37m'
        hyperlink_urls '\x1b[37m' "$body_file"
        printf '\x1b[0m'
    fi
    echo ""

    if [[ "$mode" == "delete" ]]; then
        printf '\nDelete this note? (y/n): '
        local answer
        if [[ -t 0 ]]; then
            read -r answer < /dev/tty || true
        else
            read -r answer || true
        fi
        if [[ "$answer" =~ ^[yY](es)?$ ]]; then
            rm -f "$note_path"
            echo "Note deleted."
        else
            echo "Cancelled."
        fi
    fi

    rm -f "$summaries_file" "$fzy_input" "$body_file"
}

# Run migration on notes.txt or notes.txt.bak
if [[ -f "${NOTES_FILE}.bak" && ! -f "$NOTES_FILE" ]]; then
    # If notes.txt.bak exists but notes.txt does not (e.g. after a restore), temporarily rename it so migrate_old_notes can pick it up!
    mv "${NOTES_FILE}.bak" "$NOTES_FILE"
fi
migrate_old_notes "${NOTES_FILE:-$HOME/notes.txt}" "$NOTES_DIR"


case "${1:-}" in
    -a|--add)
        shift
        add_note "$@"
        ;;
    -D)
        shift
        list_notes "delete"
        ;;
    -h|--help)
        usage
        ;;
    "")
        list_notes
        ;;
    *)
        add_note "$@"
        ;;
esac
