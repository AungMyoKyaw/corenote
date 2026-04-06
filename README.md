# corenote

[![CI](https://github.com/AungMyoKyaw/corenote/actions/workflows/ci.yml/badge.svg)](https://github.com/AungMyoKyaw/corenote/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-15.0%2B-blue)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)

A fast, native CLI frontend to Apple Notes.

Read, create, edit, search, and organize your Apple Notes directly from the terminal. No syncing, no API keys — corenote talks directly to the local Notes database.

## Features

- **Full CRUD** — list, show, create, edit, delete, and move notes
- **Folder management** — create, rename, delete, and nest folders
- **Fuzzy matching** — find notes by approximate title (exact > prefix > contains > Levenshtein)
- **Markdown support** — write in Markdown, corenote converts to/from Apple Notes format
- **`$EDITOR` integration** — create and edit notes in your preferred editor
- **JSON output** — pipe structured data to jq, scripts, or other tools with `--json`
- **Full-text search** — search across all note titles and content
- **Fast & native** — compiled Swift binary with direct SQLite access

## Requirements

- **macOS 15.0** (Sequoia) or later
- **Full Disk Access** — corenote reads `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`. Grant Full Disk Access to your terminal app in **System Settings > Privacy & Security > Full Disk Access**.

## Installation

### Homebrew (recommended)

```sh
brew tap AungMyoKyaw/tap
brew install corenote
```

### Build from source

```sh
git clone https://github.com/AungMyoKyaw/corenote.git
cd corenote
swift build -c release
cp .build/release/corenote /usr/local/bin/
```

## Usage

### List notes

```sh
# List recent notes
corenote list

# Filter by folder, sort by title
corenote list --folder Work --sort title

# JSON output
corenote list --json --limit 10
```

### Show a note

```sh
# Fuzzy match by title
corenote show "meeting notes"

# Show by internal ID
corenote show 42 --id

# Raw text without formatting
corenote show "my note" --raw
```

### Search

```sh
# Full-text search
corenote search "project deadline"

# Search within a folder
corenote search "TODO" --folder Personal
```

### Create a note

```sh
# Quick create
corenote create --title "Shopping List" --body "- Milk\n- Eggs\n- Bread"

# Create in a specific folder
corenote create --title "Sprint Plan" --folder Work

# Open in your editor
corenote create --editor
```

### Edit a note

```sh
# Open in $EDITOR (fuzzy match by title)
corenote edit "shopping list"

# Update title
corenote edit "old title" --title "New Title"

# Replace body with Markdown
corenote edit "my note" --body "# Updated\n\nNew content here."
```

### Delete a note

```sh
# Move to Recently Deleted
corenote delete "old note"

# Permanently delete (cannot be undone)
corenote delete "old note" --permanent --force
```

### Move a note

```sh
# Move to another folder
corenote move "meeting notes" --to Archive
```

### Manage folders

```sh
# List all folders
corenote folder list

# Create a folder
corenote folder create "Projects"

# Create a nested folder
corenote folder create "Q2" --parent Projects

# Rename a folder
corenote folder rename "Projects" --name "All Projects"

# Delete a folder
corenote folder delete "Old Folder"
```

## How it works

corenote reads and writes directly to the Apple Notes SQLite database (`NoteStore.sqlite`). Note bodies are stored as compressed protobuf — corenote handles the gzip decompression, protobuf decoding, and Markdown conversion transparently.

```
CLI Commands
    |
Output Formatter / JSON
    |
Core Services (fuzzy match, editor, markdown)
    |
Database Layer (SQLite + Protobuf codec)
    |
~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite
```

> **Note**: If Notes.app is running while you make changes, corenote will warn you about potential sync conflicts.

## License

[MIT](LICENSE)
