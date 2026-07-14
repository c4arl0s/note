# note

Command-line tool for creating and browsing notes using standard input and [fzy](https://github.com/junegunn/fzy).

## Requirements

- `fzy` at `/opt/homebrew/bin/fzy`

## Installation

Run the install script:

```bash
./install.sh
```

This creates a symbolic link at `/usr/local/bin/note`.

Manual install:

```bash
chmod +x note.sh
sudo ln -s "$(pwd)/note.sh" /usr/local/bin/note
```

## Usage

Add a note interactively:

```bash
./note.sh -a "This is the title of a note"
```

The interactive prompt launches a terminal-based editor where you can:
- Navigate and edit any line of the note using the **Arrow keys**.
- Edit text using standard keys (Backspace, Delete, Enter to split lines).
- Use standard line editing shortcuts: **Ctrl+A** (Home), **Ctrl+E** (End), **Ctrl+U** (clear to start of line), and **Ctrl+K** (clear to end of line).

Save and exit with any of these:
- Type a line with only `.` and press Enter
- Type a line with only `EOF` and press Enter
- Press **Ctrl+D** from anywhere to save the note immediately

Save a note directly without typing interactively:

```bash
./note.sh -a -m "Remember to call John" "Reminder"
```

Save from a file:

```bash
./note.sh -a -f ./draft.txt "Meeting notes"
```

Save using your editor (`$EDITOR`, default `nano`):

```bash
./note.sh -a -e "Meeting notes"
```

Pipe content into the script:

```bash
cat notes.md | ./note.sh -a "Meeting notes"
```

List and search notes with fzy (with the latest note on top of the list), then print the selected note to stdout (default behavior when no arguments are provided):

```bash
./note.sh
```

Shortcut to add a note (same as `-a`):

```bash
./note.sh "This is the title of a note"
```

Notes preserve multiple lines and empty lines exactly as written.

Notes are saved to `~/notes.txt`, one line per note:

```
2026-07-04 12:59 : Meeting notes : (1. First step\n2. Second step\n\n3. Third step)
```

Multi-line content is stored with `\n` inside the parentheses. Older note formats are still supported when listing.
