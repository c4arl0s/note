# note

Command-line tool for creating and browsing notes using standard input and [fzy](https://github.com/junegunn/fzy).

## Requirements

- `fzy` at `/opt/homebrew/bin/fzy`
- `glow` at `/opt/homebrew/bin/glow` (optional, for rendering markdown notes)

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

The interactive prompt opens **vim** where you can write your note with full text-editing and navigation capabilities.

Save and exit vim by saving the file and quitting (`:wq` or `:x` or `ZZ`).

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

Delete a note interactively with fzy (displays the selected note and prompts for confirmation before deletion):

```bash
./note.sh -D
```

Edit a note interactively with fzy (opens the selected note in vim for editing, and displays the updated note when finished):

```bash
./note.sh -E
```

Shortcut to add a note (same as `-a`):

```bash
./note.sh "This is the title of a note"
```

Notes preserve multiple lines and empty lines exactly as written. Any HTTP/HTTPS URL links in the note are automatically highlighted as blue, underlined hyperlinks, allowing you to open them directly in your default web browser (like Safari) by clicking (or Cmd-clicking) them.

Notes are saved inside `~/notes/` as separate `.txt` files. The file name is generated automatically based on the note's title (using lowercase and hyphens).

Inside each note file, metadata headers are stored at the top:

```
Date: 2026-07-04 12:59
Title: Meeting notes

1. First step
2. Second step

3. Third step
```
