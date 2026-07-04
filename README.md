# note

Command-line tool for creating and browsing notes using standard input and [fzy](https://github.com/junegunn/fzy).

## Requirements

- `fzy` at `/opt/homebrew/bin/fzy`

## Installation

```bash
chmod +x note.sh
```

Optional: add the directory to your `PATH` or symlink the script:

```bash
sudo ln -s "$(pwd)/note.sh" /usr/local/bin/note
```

## Usage

Add a note from stdin:

```bash
./note.sh -a "This is the title of a note"
```

Type the note content, then press **Ctrl+D** to save.

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

Notes are saved to `~/notes.txt` using blocks:

```
<<<NOTE>>>
This is the title of a note
2026-07-04 12:59
1. First step
2. Second step

3. Third step
<<<END>>>
```

Older single-line notes are still supported when listing and viewing.
