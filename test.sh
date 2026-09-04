#!/usr/bin/env bash
# ==============================================================================
# test.sh - Automated test suite for note.sh
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTE_SCRIPT="$SCRIPT_DIR/note.sh"

# ANSI Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temporary sandbox directory for tests
SANDBOX_DIR=""

setup_suite() {
    if [[ ! -f "$NOTE_SCRIPT" ]]; then
        echo -e "${RED}Error: note.sh not found at $NOTE_SCRIPT${NC}" >&2
        exit 1
    fi
    chmod +x "$NOTE_SCRIPT"
}

setup_test() {
    SANDBOX_DIR=$(mktemp -d)
    export HOME="$SANDBOX_DIR/home"
    export NOTES_DIR="$SANDBOX_DIR/notes"
    export NOTES_FILE="$SANDBOX_DIR/notes.txt"
    export MOCK_BIN="$SANDBOX_DIR/mock_bin"

    mkdir -p "$HOME" "$NOTES_DIR" "$MOCK_BIN"

    # Default dummy fzy mock (prints first line of input if available)
    cat > "$MOCK_BIN/fzy" << 'EOF'
#!/usr/bin/env bash
head -n 1
EOF
    chmod +x "$MOCK_BIN/fzy"
    export FZY="$MOCK_BIN/fzy"

    # Default dummy glow mock (prints markdown input as plain text)
    cat > "$MOCK_BIN/glow" << 'EOF'
#!/usr/bin/env bash
if [[ "$#" -gt 0 && -f "${@: -1}" ]]; then
    cat "${@: -1}"
else
    cat
fi
EOF
    chmod +x "$MOCK_BIN/glow"
    export GLOW="$MOCK_BIN/glow"

    export PATH="$MOCK_BIN:$PATH"
}

teardown_test() {
    if [[ -n "$SANDBOX_DIR" && -d "$SANDBOX_DIR" ]]; then
        rm -rf "$SANDBOX_DIR"
    fi
}

run_test() {
    local test_func="$1"
    local test_desc="$2"
    TESTS_RUN=$((TESTS_RUN + 1))

    setup_test
    echo -ne "  ${BLUE}[TEST]${NC} $test_desc ... "
    
    # Run test function in a subshell to avoid env leakage
    local error_msg
    if error_msg=$( ( "$test_func" ) 2>&1 ); then
        echo -e "${GREEN}PASSED${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAILED${NC}"
        if [[ -n "$error_msg" ]]; then
            echo -e "    ${RED}Reason:${NC} $error_msg"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    teardown_test
}

# ------------------------------------------------------------------------------
# Assertion Utilities
# ------------------------------------------------------------------------------

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="${3:-Values do not match}"

    if [[ "$expected" != "$actual" ]]; then
        echo "Assertion failed: $label (Expected: '$expected', Got: '$actual')" >&2
        return 1
    fi
}

assert_contains() {
    local needle="$1"
    local haystack="$2"
    local label="${3:-Pattern not found in string}"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "Assertion failed: $label (Expected to find: '$needle' in '$haystack')" >&2
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local label="${2:-File does not exist}"

    if [[ ! -f "$file" ]]; then
        echo "Assertion failed: $label ($file)" >&2
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local label="${2:-File unexpectedly exists}"

    if [[ -f "$file" ]]; then
        echo "Assertion failed: $label ($file)" >&2
        return 1
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local label="${3:-Exit code mismatch}"

    if [[ "$expected" -ne "$actual" ]]; then
        echo "Assertion failed: $label (Expected code $expected, got $actual)" >&2
        return 1
    fi
}

# ------------------------------------------------------------------------------
# Test Cases
# ------------------------------------------------------------------------------

test_help_flag() {
    local out
    out=$("$NOTE_SCRIPT" -h 2>&1)
    local code=$?
    assert_exit_code 0 $code "Help command should exit with 0"
    assert_contains "Usage:" "$out" "Help output should contain 'Usage:'"

    out=$("$NOTE_SCRIPT" --help 2>&1)
    code=$?
    assert_exit_code 0 $code "--help should exit with 0"
    assert_contains "Usage:" "$out" "Help output should contain 'Usage:'"
}

test_unknown_option() {
    local out
    out=$("$NOTE_SCRIPT" --invalid-flag 2>&1)
    local code=$?
    assert_exit_code 1 $code "Invalid option should exit with 1"
    assert_contains "unknown option" "$out" "Output should state unknown option"
}

test_missing_title_error() {
    local out
    out=$("$NOTE_SCRIPT" -a -m "Some content" 2>&1)
    local code=$?
    assert_exit_code 1 $code "Adding without title should exit with 1"
    assert_contains "title is required" "$out" "Should output error about missing title"
}

test_add_note_with_message() {
    local out
    out=$("$NOTE_SCRIPT" -a -m "Buy groceries\nMilk, Bread, Eggs" "Shopping List" 2>&1)
    local code=$?
    assert_exit_code 0 $code "Note addition should exit with 0"

    local expected_file="$NOTES_DIR/shopping-list.txt"
    assert_file_exists "$expected_file" "Note file should be created"

    local content
    content=$(<"$expected_file")
    assert_contains "Title: Shopping List" "$content" "File should contain Title header"
    assert_contains "Date:" "$content" "File should contain Date header"
    assert_contains "Buy groceries" "$content" "File should contain body content"
}

test_add_note_shortcut() {
    local out
    out=$("$NOTE_SCRIPT" -m "Direct message content" "Quick Note" 2>&1)
    local code=$?
    assert_exit_code 0 $code "Shortcut addition should exit with 0"

    local expected_file="$NOTES_DIR/quick-note.txt"
    assert_file_exists "$expected_file" "Note file should be created"

    local content
    content=$(<"$expected_file")
    assert_contains "Title: Quick Note" "$content" "File should contain Title header"
    assert_contains "Direct message content" "$content" "File should contain message"
}

test_add_note_from_file() {
    local source_file="$SANDBOX_DIR/source.txt"
    echo "Content from draft file" > "$source_file"
    echo "Second line in draft" >> "$source_file"

    local out
    out=$("$NOTE_SCRIPT" -a -f "$source_file" "File Import Note" 2>&1)
    local code=$?
    assert_exit_code 0 $code "Adding note from file should exit with 0"

    local expected_file="$NOTES_DIR/file-import-note.txt"
    assert_file_exists "$expected_file" "Note file should exist"

    local content
    content=$(<"$expected_file")
    assert_contains "Content from draft file" "$content" "Content should match imported file"
    assert_contains "Second line in draft" "$content" "Second line should be preserved"
}

test_add_note_from_file_not_found() {
    local out
    out=$("$NOTE_SCRIPT" -a -f "$SANDBOX_DIR/nonexistent.txt" "Nonexistent" 2>&1)
    local code=$?
    assert_exit_code 1 $code "Missing input file should exit with 1"
    assert_contains "file not found" "$out" "Should output file not found error"
}

test_add_note_from_stdin() {
    local out
    out=$(echo -e "Line 1 from stdin\nLine 2 from stdin" | "$NOTE_SCRIPT" -a "Piped Note" 2>&1)
    local code=$?
    assert_exit_code 0 $code "Piped note addition should exit with 0"

    local expected_file="$NOTES_DIR/piped-note.txt"
    assert_file_exists "$expected_file" "Note file should exist"

    local content
    content=$(<"$expected_file")
    assert_contains "Line 1 from stdin" "$content" "Line 1 should be present"
    assert_contains "Line 2 from stdin" "$content" "Line 2 should be present"
}

test_add_note_with_editor() {
    # Create mock editor that writes content to the target file
    cat > "$MOCK_BIN/mock_editor" << 'EOF'
#!/usr/bin/env bash
echo "Content generated by custom editor" > "$1"
EOF
    chmod +x "$MOCK_BIN/mock_editor"
    export EDITOR="$MOCK_BIN/mock_editor"

    local out
    out=$("$NOTE_SCRIPT" -a -e "Editor Note" 2>&1)
    local code=$?
    assert_exit_code 0 $code "Editor note addition should exit with 0"

    local expected_file="$NOTES_DIR/editor-note.txt"
    assert_file_exists "$expected_file" "Note file should exist"

    local content
    content=$(<"$expected_file")
    assert_contains "Content generated by custom editor" "$content" "Content should match editor output"
}

test_empty_note_rejected() {
    local out
    out=$("$NOTE_SCRIPT" -a -m "   " "Blank Note" 2>&1)
    local code=$?
    assert_exit_code 0 $code "Empty note submission handled gracefully"
    assert_contains "Note not saved (empty content)" "$out" "Should report empty content"
    assert_file_not_exists "$NOTES_DIR/blank-note.txt" "Empty note file should not be saved"
}

test_filename_sanitization_and_collision() {
    # Special characters in title
    "$NOTE_SCRIPT" -a -m "Alpha content" "Project: Alpha / Beta (v2.0)!" >/dev/null 2>&1
    local expected_file1="$NOTES_DIR/project-alpha-beta-v2-0.txt"
    assert_file_exists "$expected_file1" "Sanitized filename should exist"

    # Collision handling (same title created again)
    "$NOTE_SCRIPT" -a -m "Alpha duplicate" "Project: Alpha / Beta (v2.0)!" >/dev/null 2>&1
    local expected_file2="$NOTES_DIR/project-alpha-beta-v2-0-1.txt"
    assert_file_exists "$expected_file2" "Collision should create -1 file"

    # Third collision
    "$NOTE_SCRIPT" -a -m "Alpha duplicate 2" "Project: Alpha / Beta (v2.0)!" >/dev/null 2>&1
    local expected_file3="$NOTES_DIR/project-alpha-beta-v2-0-2.txt"
    assert_file_exists "$expected_file3" "Collision should create -2 file"
}

test_multiline_and_empty_lines_preserved() {
    local input="Paragraph 1\n\nParagraph 2\n\n- Item 1\n- Item 2"
    echo -e "$input" | "$NOTE_SCRIPT" -a "Multi Line Note" >/dev/null 2>&1

    local expected_file="$NOTES_DIR/multi-line-note.txt"
    assert_file_exists "$expected_file" "Note file should exist"

    local content
    content=$(<"$expected_file")
    assert_contains "Paragraph 1" "$content" "Paragraph 1 should exist"
    assert_contains "Paragraph 2" "$content" "Paragraph 2 should exist"
    assert_contains "- Item 1" "$content" "Item 1 should exist"
}

test_list_notes_empty() {
    local out
    out=$("$NOTE_SCRIPT" 2>&1)
    local code=$?
    assert_exit_code 0 $code "Empty list should exit with 0"
    assert_contains "No notes found" "$out" "Should output 'No notes found.'"
}

test_list_notes_with_selection() {
    "$NOTE_SCRIPT" -a -m "Content of note one" "Note One" >/dev/null 2>&1
    "$NOTE_SCRIPT" -a -m "Content of note two" "Note Two" >/dev/null 2>&1

    # Mock fzy to select the line containing "Note One"
    cat > "$MOCK_BIN/fzy" << 'EOF'
#!/usr/bin/env bash
grep "Note One"
EOF
    chmod +x "$MOCK_BIN/fzy"

    local out
    out=$("$NOTE_SCRIPT" 2>&1)
    local code=$?
    assert_exit_code 0 $code "Listing and selecting note should succeed"
    assert_contains "Note One" "$out" "Output should contain selected note title"
    assert_contains "Content of note one" "$out" "Output should contain selected note content"
}

test_list_notes_newest_first_sorting() {
    # Create notes with explicit dates
    mkdir -p "$NOTES_DIR"
    cat > "$NOTES_DIR/old-note.txt" << 'EOF'
Date: 2026-01-01 10:00
Title: Old Note

Old content
EOF

    cat > "$NOTES_DIR/new-note.txt" << 'EOF'
Date: 2026-08-01 12:00
Title: New Note

New content
EOF

    # Mock fzy to verify the order of piped input
    cat > "$MOCK_BIN/fzy" << 'EOF'
#!/usr/bin/env bash
# Capture stdin to a temporary file
cat > "$HOME/fzy_received_input.txt"
# Return first line
head -n 1 "$HOME/fzy_received_input.txt"
EOF
    chmod +x "$MOCK_BIN/fzy"

    "$NOTE_SCRIPT" >/dev/null 2>&1

    local first_line
    first_line=$(head -n 1 "$HOME/fzy_received_input.txt")

    assert_contains "New Note" "$first_line" "First item in fzy input should be the newer note"
}

test_list_notes_fzy_lines_flag() {
    "$NOTE_SCRIPT" -a -m "Content of note" "Note For Lines Test" >/dev/null 2>&1

    # Mock fzy to record arguments passed to it
    cat > "$MOCK_BIN/fzy" << 'EOF'
#!/usr/bin/env bash
echo "$*" > "$HOME/fzy_args.txt"
head -n 1
EOF
    chmod +x "$MOCK_BIN/fzy"

    # Test default 25 lines
    "$NOTE_SCRIPT" >/dev/null 2>&1
    local default_args
    default_args=$(<"$HOME/fzy_args.txt")
    assert_contains "-l 25" "$default_args" "fzy should be called with default -l 25"

    # Test custom FZY_LINES environment variable override
    FZY_LINES=35 "$NOTE_SCRIPT" >/dev/null 2>&1
    local custom_args
    custom_args=$(<"$HOME/fzy_args.txt")
    assert_contains "-l 35" "$custom_args" "fzy should be called with custom -l 35 when FZY_LINES is set"
}

test_delete_note_confirm_yes() {
    "$NOTE_SCRIPT" -a -m "Note to delete" "Delete Me" >/dev/null 2>&1
    local note_file="$NOTES_DIR/delete-me.txt"
    assert_file_exists "$note_file" "Note file should exist before deletion"

    # Confirm deletion with 'y'
    local out
    out=$(echo "y" | "$NOTE_SCRIPT" -D 2>&1)
    local code=$?
    assert_exit_code 0 $code "Deletion command should exit with 0"
    assert_contains "Note deleted" "$out" "Output should confirm note deletion"
    assert_file_not_exists "$note_file" "Note file should be removed"
}

test_delete_note_cancel_no() {
    "$NOTE_SCRIPT" -a -m "Keep this note" "Keep Me" >/dev/null 2>&1
    local note_file="$NOTES_DIR/keep-me.txt"
    assert_file_exists "$note_file" "Note file should exist"

    # Cancel deletion with 'n'
    local out
    out=$(echo "n" | "$NOTE_SCRIPT" -D 2>&1)
    local code=$?
    assert_exit_code 0 $code "Cancel deletion should exit with 0"
    assert_contains "Cancelled" "$out" "Output should report Cancelled"
    assert_file_exists "$note_file" "Note file should not be removed"
}

test_edit_note() {
    "$NOTE_SCRIPT" -a -m "Original content" "Edit Note" >/dev/null 2>&1
    local note_file="$NOTES_DIR/edit-note.txt"
    assert_file_exists "$note_file" "Note file should exist before edit"

    # Mock vim/vi to append updated line
    cat > "$MOCK_BIN/vim" << 'EOF'
#!/usr/bin/env bash
echo "Appended during edit" >> "$1"
EOF
    chmod +x "$MOCK_BIN/vim"

    local out
    out=$("$NOTE_SCRIPT" -E 2>&1)
    local code=$?
    assert_exit_code 0 $code "Editing note should exit with 0"
    assert_contains "Note updated" "$out" "Output should indicate Note updated"

    local content
    content=$(<"$note_file")
    assert_contains "Appended during edit" "$content" "Edited file should contain updated text"
}

test_copy_note_to_clipboard() {
    "$NOTE_SCRIPT" -a -m "Copyable content for clipboard" "Clipboard Note" >/dev/null 2>&1

    # Mock fzy to select "Clipboard Note"
    cat > "$MOCK_BIN/fzy" << 'EOF'
#!/usr/bin/env bash
grep "Clipboard Note"
EOF
    chmod +x "$MOCK_BIN/fzy"

    # Mock pbcopy to write stdin to a temporary file
    cat > "$MOCK_BIN/pbcopy" << 'EOF'
#!/usr/bin/env bash
cat > "$HOME/mock_clipboard.txt"
EOF
    chmod +x "$MOCK_BIN/pbcopy"

    # Test -c flag
    local out
    out=$("$NOTE_SCRIPT" -c 2>&1)
    local code=$?
    assert_exit_code 0 $code "Copy note command with -c should exit with 0"
    assert_contains "Clipboard Note" "$out" "Output should display the note"
    assert_contains "Note was also passed to the clipboard." "$out" "Output should report note was copied to clipboard"

    local copied_content
    copied_content=$(<"$HOME/mock_clipboard.txt")
    assert_contains "Clipboard Note" "$copied_content" "Clipboard should receive note title"
    assert_contains "Copyable content for clipboard" "$copied_content" "Clipboard should receive note body"

    # Test -C flag alias
    rm -f "$HOME/mock_clipboard.txt"
    local out_C
    out_C=$("$NOTE_SCRIPT" -C 2>&1)
    local code_C=$?
    assert_exit_code 0 $code_C "Copy note command with -C should exit with 0"
    assert_contains "Note was also passed to the clipboard." "$out_C" "Output should report note was copied to clipboard for -C"
    assert_file_exists "$HOME/mock_clipboard.txt" "Clipboard file should be populated with -C"
}

test_legacy_migration_block_format() {
    # Create legacy monolithic notes.txt with <<<NOTE>>> format
    cat > "$NOTES_FILE" << 'EOF'
<<<NOTE>>>
2026-05-10 14:30
Legacy Block Note
This is a legacy note body with multiple lines.
<<<END>>>
EOF

    # Running note.sh should trigger migrate_old_notes
    "$NOTE_SCRIPT" -a -m "Trigger note" "Trigger" >/dev/null 2>&1

    # Check migrated note in NOTES_DIR
    local migrated_file="$NOTES_DIR/legacy-block-note.txt"
    assert_file_exists "$migrated_file" "Migrated block note file should exist"

    local content
    content=$(<"$migrated_file")
    assert_contains "Date: 2026-05-10 14:30" "$content" "Migrated note should have Date header"
    assert_contains "Title: Legacy Block Note" "$content" "Migrated note should have Title header"
    assert_contains "This is a legacy note body" "$content" "Migrated note should preserve body"

    # Original notes.txt should be moved to notes.txt.bak
    assert_file_exists "${NOTES_FILE}.bak" "Old notes.txt should be renamed to .bak"
}

test_legacy_migration_single_line_format() {
    # Create legacy monolithic notes.txt with single line format
    cat > "$NOTES_FILE" << 'EOF'
2026-04-20 09:15 : Single Line Note : (First line\nSecond line)
EOF

    # Running note.sh should trigger migrate_old_notes
    "$NOTE_SCRIPT" -a -m "Trigger note" "Trigger" >/dev/null 2>&1

    local migrated_file="$NOTES_DIR/single-line-note.txt"
    assert_file_exists "$migrated_file" "Migrated single line note file should exist"

    local content
    content=$(<"$migrated_file")
    assert_contains "Date: 2026-04-20 09:15" "$content" "Migrated note should have Date header"
    assert_contains "Title: Single Line Note" "$content" "Migrated note should have Title header"
    assert_contains "First line" "$content" "Migrated note should decode newline correctly"
    assert_contains "Second line" "$content" "Migrated note should decode newline correctly"
}

# ------------------------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------------------------

setup_suite

echo -e "\n${BOLD}======================================================${NC}"
echo -e "${BOLD} Running note.sh Test Suite${NC}"
echo -e "${BOLD}======================================================${NC}\n"

echo -e "${BOLD}CLI Options & Flags:${NC}"
run_test test_help_flag "Help flag (-h / --help)"
run_test test_unknown_option "Unknown option error handling"
run_test test_missing_title_error "Missing title error handling"

echo -e "\n${BOLD}Adding Notes:${NC}"
run_test test_add_note_with_message "Add note with -m/--message"
run_test test_add_note_shortcut "Add note via shortcut arguments"
run_test test_add_note_from_file "Add note from file (-f/--file)"
run_test test_add_note_from_file_not_found "Add note with non-existent file error"
run_test test_add_note_from_stdin "Add note via piped stdin"
run_test test_add_note_with_editor "Add note with editor (-e/--editor)"
run_test test_empty_note_rejected "Reject saving note with empty content"
run_test test_filename_sanitization_and_collision "Filename sanitization and collision deduplication"
run_test test_multiline_and_empty_lines_preserved "Preserve multiline content and formatting"

echo -e "\n${BOLD}Listing & Searching:${NC}"
run_test test_list_notes_empty "Listing with no notes"
run_test test_list_notes_with_selection "Listing notes and selecting with fzy"
run_test test_list_notes_newest_first_sorting "Sorting notes newest first"
run_test test_list_notes_fzy_lines_flag "Pass -l LINES to fzy (default and custom FZY_LINES)"

echo -e "\n${BOLD}Interactive Operations:${NC}"
run_test test_delete_note_confirm_yes "Delete note with confirmation (yes)"
run_test test_delete_note_cancel_no "Cancel note deletion (no)"
run_test test_edit_note "Edit note interactively (-E)"
run_test test_copy_note_to_clipboard "Copy note to clipboard (-c / -C)"

echo -e "\n${BOLD}Legacy Migration:${NC}"
run_test test_legacy_migration_block_format "Migrate legacy block format notes.txt"
run_test test_legacy_migration_single_line_format "Migrate legacy single-line format notes.txt"

echo -e "\n${BOLD}======================================================${NC}"
echo -e " Tests Completed: ${TESTS_RUN}"
echo -e " ${GREEN}Passed: ${TESTS_PASSED}${NC}"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    echo -e " ${RED}Failed: ${TESTS_FAILED}${NC}"
    echo -e "${BOLD}======================================================${NC}\n"
    exit 1
else
    echo -e " ${GREEN}All tests passed successfully!${NC}"
    echo -e "${BOLD}======================================================${NC}\n"
    exit 0
fi
