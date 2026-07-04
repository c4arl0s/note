# note

Command-line tool for creating and browsing notes using [dialog](https://invisible-island.net/dialog/) and [fzy](https://github.com/junegunn/fzy).

## Requirements

- `dialog` at `/opt/homebrew/bin/dialog`
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

Add a note:

```bash
./note.sh -a "This is the title of a note"
```

List and search notes with fzy, then view the selected note in a dialog:

```bash
./note.sh -l
```

Shortcut to add a note (same as `-a`):

```bash
./note.sh "This is the title of a note"
```

When adding a note, use **Save** to store it or **Cancel** to discard.

Notes are saved to `~/notes.txt`, one per line:

```
2026-07-04 12:59 : (This is a new note)
2026-07-04 13:58 : (This is a second note)
```
