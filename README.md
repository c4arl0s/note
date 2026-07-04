# note

Command-line tool for creating notes using [dialog](https://invisible-island.net/dialog/).

## Requirements

- `dialog` installed at `/opt/homebrew/bin/dialog`

## Installation

```bash
chmod +x note
```

Optional: add the directory to your `PATH` or symlink the script to a directory in your `PATH`:

```bash
sudo ln -s "$(pwd)/note" /usr/local/bin/note
```

## Usage

```bash
note "This is the title of a note"
```

This opens a dialog box to write the note. Use **Save** to store it or **Cancel** to discard.

Notes are saved to `~/notes.txt`, one per line:

```
2026-07-04 12:59 : (This is a new note)
2026-07-04 13:58 : (This is a second note)
```
