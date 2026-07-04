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

Save with any of these:
- Type a line with only `.` and press Enter
- Type a line with only `EOF` and press Enter
- Press Ctrl+D on an empty line

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

List and search notes with fzy, then print the selected note to stdout:

```bash
./note.sh -l
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
