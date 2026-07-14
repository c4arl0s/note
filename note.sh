#!/usr/bin/env bash

FZY="/opt/homebrew/bin/fzy"
NOTES_FILE="${NOTES_FILE:-$HOME/notes.txt}"

NOTE_START="<<<NOTE>>>"
NOTE_END="<<<END>>>"
INPUT_END_MARKER="."

usage() {
    cat >&2 <<EOF
Usage:
  $(basename "$0")                            List and search notes
  $(basename "$0") -a [options] "<title>"   Add a note
  $(basename "$0") [options] "<title>"        Add a note (shortcut)

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

hyperlink_urls() {
    sed -E 's|(https?://[^]'"'"'`()<>[:space:]]*[^]'"'"'`()<>[:space:].,;:!?])|\x1b[4;34m\1\x1b[0m|g' "$@"
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
    local temp_py
    temp_py=$(mktemp)

    cat << 'EOF' > "$temp_py"
import sys
import curses

def main(stdscr):
    # Enable color support
    curses.use_default_colors()
    try:
        curses.curs_set(1)
    except curses.error:
        pass
    stdscr.keypad(True)
    
    # Text buffer
    lines = [""]
    cursor_y = 0  # index in lines
    cursor_x = 0  # index in lines[cursor_y]
    
    # Scroll offsets
    top_line = 0
    left_col = 0
    
    prompt = [
        "Enter your note below.",
        "",
        "Save with any of these:",
        "  - A line containing only \".\"",
        "  - A line containing only \"EOF\"",
        "  - Ctrl+D on an empty line",
        "-" * 40
    ]
    prompt_len = len(prompt)
    
    while True:
        height, width = stdscr.getmaxyx()
        max_rows = height - prompt_len - 1
        max_cols = width - 1
        
        if max_rows <= 0 or max_cols <= 0:
            # Terminal is too small
            stdscr.clear()
            stdscr.addstr(0, 0, "Terminal too small!")
            stdscr.refresh()
            ch = stdscr.get_wch()
            if ch == curses.KEY_RESIZE:
                continue
            elif ch == '\x04': # Ctrl+D
                break
            continue
            
        # Adjust vertical scrolling
        if cursor_y < top_line:
            top_line = cursor_y
        elif cursor_y >= top_line + max_rows:
            top_line = cursor_y - max_rows + 1
            
        # Adjust horizontal scrolling
        if cursor_x < left_col:
            left_col = cursor_x
        elif cursor_x >= left_col + max_cols:
            left_col = cursor_x - max_cols + 1
            
        stdscr.clear()
        
        # Draw prompt
        for i, p_line in enumerate(prompt):
            if i < height:
                stdscr.addstr(i, 0, p_line[:width-1])
                
        # Draw text
        for i in range(max_rows):
            line_idx = top_line + i
            if line_idx >= len(lines):
                break
            row = prompt_len + i
            if row < height - 1:
                line_content = lines[line_idx]
                visible_content = line_content[left_col:left_col + max_cols]
                stdscr.addstr(row, 0, visible_content)
                
        # Position cursor
        stdscr.move(prompt_len + cursor_y - top_line, cursor_x - left_col)
        stdscr.refresh()
        
        try:
            ch = stdscr.get_wch()
        except KeyboardInterrupt:
            raise
        except Exception:
            continue
            
        # Handle key input
        if isinstance(ch, int):
            if ch == curses.KEY_UP:
                if cursor_y > 0:
                    cursor_y -= 1
                    cursor_x = min(cursor_x, len(lines[cursor_y]))
            elif ch == curses.KEY_DOWN:
                if cursor_y < len(lines) - 1:
                    cursor_y += 1
                    cursor_x = min(cursor_x, len(lines[cursor_y]))
            elif ch == curses.KEY_LEFT:
                if cursor_x > 0:
                    cursor_x -= 1
                elif cursor_y > 0:
                    cursor_y -= 1
                    cursor_x = len(lines[cursor_y])
            elif ch == curses.KEY_RIGHT:
                if cursor_x < len(lines[cursor_y]):
                    cursor_x += 1
                elif cursor_y < len(lines) - 1:
                    cursor_y += 1
                    cursor_x = 0
            elif ch == curses.KEY_HOME:
                cursor_x = 0
            elif ch == curses.KEY_END:
                cursor_x = len(lines[cursor_y])
            elif ch == curses.KEY_BACKSPACE:
                if cursor_x > 0:
                    current_line = lines[cursor_y]
                    lines[cursor_y] = current_line[:cursor_x - 1] + current_line[cursor_x:]
                    cursor_x -= 1
                elif cursor_y > 0:
                    prev_line = lines[cursor_y - 1]
                    cursor_x = len(prev_line)
                    lines[cursor_y - 1] = prev_line + lines[cursor_y]
                    lines.pop(cursor_y)
                    cursor_y -= 1
            elif ch == curses.KEY_DC: # Delete
                current_line = lines[cursor_y]
                if cursor_x < len(current_line):
                    lines[cursor_y] = current_line[:cursor_x] + current_line[cursor_x + 1:]
                elif cursor_y < len(lines) - 1:
                    lines[cursor_y] = current_line + lines[cursor_y + 1]
                    lines.pop(cursor_y + 1)
            elif ch == curses.KEY_RESIZE:
                pass
                
        elif isinstance(ch, str):
            # Check Ctrl keys
            if ch == '\x04': # Ctrl+D
                break
            elif ch == '\x01': # Ctrl+A (Home)
                cursor_x = 0
            elif ch == '\x05': # Ctrl+E (End)
                cursor_x = len(lines[cursor_y])
            elif ch == '\x15': # Ctrl+U
                lines[cursor_y] = lines[cursor_y][cursor_x:]
                cursor_x = 0
            elif ch == '\x0b': # Ctrl+K
                lines[cursor_y] = lines[cursor_y][:cursor_x]
            elif ch in ('\n', '\r'):
                # Enter key pressed
                current_line = lines[cursor_y]
                if current_line == "." or current_line == "EOF":
                    lines.pop(cursor_y)
                    break
                # Split line
                left = current_line[:cursor_x]
                right = current_line[cursor_x:]
                lines[cursor_y] = left
                lines.insert(cursor_y + 1, right)
                cursor_y += 1
                cursor_x = 0
            elif ch in ('\x7f', '\x08', '\b'): # Backspace characters
                if cursor_x > 0:
                    current_line = lines[cursor_y]
                    lines[cursor_y] = current_line[:cursor_x - 1] + current_line[cursor_x:]
                    cursor_x -= 1
                elif cursor_y > 0:
                    prev_line = lines[cursor_y - 1]
                    cursor_x = len(prev_line)
                    lines[cursor_y - 1] = prev_line + lines[cursor_y]
                    lines.pop(cursor_y)
                    cursor_y -= 1
            else:
                # General characters (including wide chars)
                if len(ch) == 1 and ord(ch) >= 32:
                    current_line = lines[cursor_y]
                    lines[cursor_y] = current_line[:cursor_x] + ch + current_line[cursor_x:]
                    cursor_x += 1

    # Write output to the file passed as argument
    output_file = sys.argv[1]
    with open(output_file, 'w', encoding='utf-8') as f:
        for line in lines:
            f.write(line + '\n')

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(1)
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        sys.exit(130)
EOF

    python3 "$temp_py" "$output_file"
    local exit_status=$?
    rm -f "$temp_py"

    if [[ $exit_status -eq 0 ]]; then
        cat >&2 <<'EOF'
Enter your note below.

Save with any of these:
  - A line containing only "."
  - A line containing only "EOF"
  - Ctrl+D on an empty line
EOF
        if [[ -f "$output_file" ]]; then
            hyperlink_urls "$output_file" >&2
        fi
    fi

    return $exit_status
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
    printf 'Date: %s\n' "$timestamp" >&2
    printf 'Title: %s\n\n' "$title" | hyperlink_urls >&2
    hyperlink_urls "$temp_out" >&2
    rm -f "$temp_out"
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

    awk -F '\t' '{ lines[NR] = $4 } END { for (i = NR; i > 0; i--) print lines[i] }' "$summaries_file" > "$fzy_input"

    selected_line=$(<"$fzy_input" "$FZY") || {
        rm -rf "$index_dir" "$summaries_file" "$fzy_input"
        return 0
    }

    if [[ -z "$selected_line" ]]; then
        rm -rf "$index_dir" "$summaries_file" "$fzy_input"
        return 0
    fi

    IFS=$'\t' read -r note_id title timestamp < <(
        selected="$selected_line" awk -F '\t' '
            BEGIN { OFS="\t" }
            $4 == ENVIRON["selected"] { note_id = $1; title = $2; timestamp = $3 }
            END { if (note_id != "") print note_id, title, timestamp }
        ' "$summaries_file"
    )
    body_file="$index_dir/$note_id.body"

    if [[ -z "$note_id" || ! -f "$body_file" ]]; then
        rm -rf "$index_dir" "$summaries_file" "$fzy_input"
        return 0
    fi

    printf 'Date: %s\n' "$timestamp"
    printf 'Title: %s\n\n' "$title" | hyperlink_urls
    hyperlink_urls "$body_file"

    rm -rf "$index_dir" "$summaries_file" "$fzy_input"
}

case "${1:-}" in
    -a|--add)
        shift
        add_note "$@"
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
