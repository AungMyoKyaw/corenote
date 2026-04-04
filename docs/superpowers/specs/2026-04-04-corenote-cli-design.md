# corenote — CLI Frontend to Apple Notes

**Date:** 2026-04-04
**Status:** Approved

## Overview

`corenote` is a Swift CLI tool that provides full management of Apple Notes via direct access to the `NoteStore.sqlite` database. It supports listing, viewing, creating, editing, deleting, and searching notes, as well as full folder management. Notes are presented and edited as Markdown, with automatic conversion to/from Apple Notes' internal protobuf format.

**Target platform:** macOS Sequoia (15+) only.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   CLI Layer                      │
│  swift-argument-parser commands & subcommands    │
│  (list, show, create, edit, delete, folder ...)  │
├─────────────────────────────────────────────────┤
│                 Output Layer                     │
│  Rich terminal (default) │ JSON (--json flag)    │
├─────────────────────────────────────────────────┤
│               Core Services                      │
│  NoteStore    │ MarkdownConverter │ FuzzyMatcher │
├─────────────────────────────────────────────────┤
│              Data Access Layer                   │
│  SQLiteManager  │  ProtobufDecoder/Encoder       │
├─────────────────────────────────────────────────┤
│           NoteStore.sqlite (on disk)             │
│  ~/Library/Group Containers/                     │
│    group.com.apple.notes/NoteStore.sqlite        │
└─────────────────────────────────────────────────┘
```

### Layers

- **CLI Layer** — Command parsing via `swift-argument-parser`, argument validation, dispatches to Core Services.
- **Output Layer** — Formats results for rich terminal display (tables, colors, rendered Markdown) or JSON (`--json` flag).
- **Core Services** — Business logic: querying notes, converting formats, fuzzy matching by title.
- **Data Access** — Raw SQLite queries via system `libsqlite3`, gzip decompression/compression, protobuf encode/decode.

### Dependencies

- `swift-argument-parser` — CLI framework
- `swift-protobuf` — Decode/encode Apple Notes' protobuf note bodies
- System `libsqlite3` — No third-party SQLite wrapper
- System `Compression` framework — gzip decompression of note bodies

## Command Interface

### Note Commands (top-level)

```
corenote list                    List all notes
  --folder <name>                  Filter by folder
  --account <name>                 Filter by account
  --limit <n>                      Max results (default: 50)
  --sort <field>                   Sort by: modified|created|title
  --json                           JSON output

corenote show <query>            Show a note's content
  --id                             Treat query as internal ID
  --raw                            Show raw plain text (no Markdown rendering)
  --json                           JSON output

corenote create                  Create a new note
  --title <text>                   Note title (required)
  --body <text>                    Note body (Markdown)
  --folder <name>                  Target folder (default: Notes)
  --editor                         Open in $EDITOR

corenote edit <query>            Edit an existing note
  --id                             Treat query as internal ID
  --body <text>                    Replace body with this text
  --title <text>                   Update title
  (default)                        Opens in $EDITOR

corenote delete <query>          Move note to Recently Deleted
  --id                             Treat query as internal ID
  --permanent                      Permanently delete
  --force                          Skip confirmation

corenote search <text>           Full-text search across notes
  --folder <name>                  Limit to folder
  --limit <n>                      Max results
  --json                           JSON output

corenote move <query>            Move note to another folder
  --to <folder>                    Target folder (required)
  --id                             Treat query as internal ID
```

### Folder Commands (namespaced)

```
corenote folder list             List all folders
  --account <name>                 Filter by account
  --json                           JSON output

corenote folder create <name>    Create a new folder
  --parent <name>                  Parent folder (for nesting)

corenote folder rename <query>   Rename a folder
  --name <new-name>                New name (required)

corenote folder delete <query>   Delete a folder
  --force                          Skip confirmation
```

### Global Options

```
--help, -h                       Show help
--version, -v                    Show version
--db <path>                      Custom database path (for testing)
```

## Project Structure

```
corenote/
├── Package.swift
├── Sources/
│   └── corenote/
│       ├── CoreNote.swift              # Root command (@main)
│       ├── Commands/
│       │   ├── ListCommand.swift
│       │   ├── ShowCommand.swift
│       │   ├── CreateCommand.swift
│       │   ├── EditCommand.swift
│       │   ├── DeleteCommand.swift
│       │   ├── SearchCommand.swift
│       │   ├── MoveCommand.swift
│       │   └── Folder/
│       │       ├── FolderGroup.swift
│       │       ├── FolderListCommand.swift
│       │       ├── FolderCreateCommand.swift
│       │       ├── FolderRenameCommand.swift
│       │       └── FolderDeleteCommand.swift
│       ├── Database/
│       │   ├── SQLiteConnection.swift   # Raw libsqlite3 wrapper
│       │   ├── NoteStoreDB.swift        # Queries against NoteStore schema
│       │   └── SchemaMapper.swift       # Maps Z_ENT values to entity types
│       ├── Models/
│       │   ├── Note.swift
│       │   ├── Folder.swift
│       │   └── Account.swift
│       ├── Protobuf/
│       │   ├── notestore.proto          # Reverse-engineered proto definition
│       │   ├── NoteBodyDecoder.swift     # gzip -> protobuf -> structured data
│       │   └── NoteBodyEncoder.swift     # structured data -> protobuf -> gzip
│       ├── Converter/
│       │   ├── MarkdownToNote.swift      # Markdown -> AttributeRuns
│       │   └── NoteToMarkdown.swift      # AttributeRuns -> Markdown
│       ├── Output/
│       │   ├── Formatter.swift          # Rich terminal output (tables, colors)
│       │   └── JSONOutput.swift         # --json output
│       └── Utilities/
│           ├── FuzzyMatcher.swift        # Fuzzy title matching
│           └── EditorLauncher.swift      # $EDITOR integration
└── Tests/
    └── corenoteTests/
        ├── SQLiteConnectionTests.swift
        ├── NoteBodyDecoderTests.swift
        ├── MarkdownConverterTests.swift
        └── FuzzyMatcherTests.swift
```

## Data Access

### Database Location

```
~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite
```

Open read-write via `sqlite3_open_v2` with `SQLITE_OPEN_READWRITE`. The `--db <path>` flag overrides this for testing.

### Entity Type Discovery

Apple's Core Data uses `Z_PRIMARYKEY` to map `Z_ENT` integer values to entity names. These values can shift between macOS versions — never hardcode them:

```sql
SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY
WHERE Z_NAME IN ('ICNote', 'ICFolder', 'ICAccount')
```

### Core Queries

**List notes:**

```sql
SELECT c.Z_PK, c.ZTITLE1, c.ZSNIPPET, c.ZIDENTIFIER,
       c.ZCREATIONDATE1, c.ZMODIFICATIONDATE1,
       f.ZTITLE2 as folder_name, a.ZNAME as account_name
FROM ZICCLOUDSYNCINGOBJECT c
LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON f.Z_PK = c.ZFOLDER
LEFT JOIN ZICCLOUDSYNCINGOBJECT a ON a.Z_PK = c.ZACCOUNT2
WHERE c.Z_ENT = :noteEnt
  AND (c.ZMARKEDFORDELETION != 1 OR c.ZMARKEDFORDELETION IS NULL)
  AND (c.ZISINTRASHEDBYUSER != 1 OR c.ZISINTRASHEDBYUSER IS NULL)
ORDER BY c.ZMODIFICATIONDATE1 DESC
```

**Get note body:**

```sql
SELECT n.ZDATA FROM ZICNOTEDATA n
JOIN ZICCLOUDSYNCINGOBJECT c ON c.ZNOTEDATA = n.Z_PK
WHERE c.Z_PK = :notePK
```

### Note Body Pipeline

```
                    READ PATH
  ZDATA (blob) -> gunzip -> protobuf decode -> Markdown output

                   WRITE PATH
  Markdown input -> protobuf encode -> gzip -> ZDATA (blob)
```

### Protobuf Structure

```
NoteStoreProto
  └── Document (field 2)
        └── Note (field 3)
              ├── note_text: string       — plain text content
              └── attribute_run: repeated — formatting spans
                    ├── length
                    ├── paragraph_style   — headings, lists, checklists
                    ├── font_weight       — bold
                    ├── underlined
                    ├── strikethrough
                    ├── link              — URLs
                    └── attachment_info   — embedded objects
```

### Markdown to AttributeRun Mapping

| Markdown | AttributeRun field |
|---|---|
| `# Heading` | `paragraph_style.style = 1` (H1), 2 (H2), etc. |
| `**bold**` | `font_weight = 1` |
| `_italic_` | `font_weight = 0` with italic font hint |
| `~~strike~~` | `strikethrough = 1` |
| `[text](url)` | `link = "url"` |
| `- item` | `paragraph_style.list_style = bullet` |
| `1. item` | `paragraph_style.list_style = numbered` |
| `- [ ] task` | `paragraph_style.checklist` |
| `> quote` | `paragraph_style.blockquote` |

### Timestamps

All timestamps are Mac Absolute Time (seconds since Jan 1, 2001):

```
unix_timestamp = mac_timestamp + 978307200
```

## Fuzzy Matching

When resolving a `<query>` to a note, the resolver follows this priority:

1. **Exact match** — title equals query (case-insensitive)
2. **Prefix match** — title starts with query
3. **Contains match** — title contains query
4. **Fuzzy match** — Levenshtein distance similarity (threshold: 60%)

### Ambiguity Handling

- 0 matches: error `No note found matching "<query>"`
- 1 match: use directly
- 2-5 matches: display numbered list, prompt user to pick
- 6+ matches: display first 10, suggest narrowing the query

### Edge Cases

- `--id` flag bypasses fuzzy logic entirely, looks up `Z_PK` or `ZIDENTIFIER`
- Very short queries (1-2 chars): exact or prefix match only, skip fuzzy
- Trashed notes excluded by default; show hint if query matches only trashed notes
- Unicode/emoji in titles: normalize for comparison

## Editor Integration

When `corenote edit <query>` is invoked without `--body`:

1. Resolve note via fuzzy matcher
2. Decode note body to Markdown
3. Write to temp file: `/tmp/corenote-<id>.md`
4. Launch `$EDITOR` (fallback chain: `vim` -> `nano` -> `vi`)
5. Wait for editor to exit
6. Read temp file, compare with original
7. If changed: convert Markdown -> protobuf -> gzip -> write to `ZDATA`
8. If unchanged: print `No changes made`
9. Clean up temp file

For `corenote create --editor`:

1. Write template to temp file: `# Title\n\n`
2. Launch editor
3. Parse first line as title, rest as body
4. Create note in database

## Output Formatting

### Rich Terminal Output (default)

**List view:**

```
$ corenote list
 #   Title                Modified          Folder
 1   Shopping List        2 hours ago       Personal
 2   Meeting Notes        Yesterday         Work
 3   API Design Doc       3 days ago        Projects

3 notes (showing all)
```

**Note detail view:**

```
$ corenote show shopping

Shopping List
═══════════════════════════════════════
Folder: Personal  │  Modified: 2 hours ago  │  Created: Jan 10, 2026

## Groceries
- [x] Milk
- [ ] Eggs
- [ ] Bread
```

**Folder list:**

```
$ corenote folder list
 Folder              Notes   Account
 Notes               12      iCloud
 Personal             8      iCloud
 Work                 5      iCloud
```

**Search results:**

```
$ corenote search "API"
 #   Title              Folder      Match
 1   API Design Doc     Projects    "...the REST API should handle..."
 2   Meeting Notes      Work        "...discussed API rate limits..."

2 notes matched "API"
```

### JSON Output (`--json`)

```json
{
  "id": 42,
  "uuid": "abc123-def456",
  "title": "Shopping List",
  "body": "## Groceries\n- [x] Milk\n...",
  "folder": "Personal",
  "account": "iCloud",
  "created": "2026-01-10T08:30:00Z",
  "modified": "2026-04-04T14:22:00Z",
  "trashed": false
}
```

List commands return JSON arrays. All dates are ISO 8601.

### Color Scheme

- **Titles** — bold white
- **Metadata labels** — dim/gray
- **Folder names** — cyan
- **Dates** — yellow
- **Checkmarks** — green (done) / red (pending)
- **Errors** — red
- **Warnings** — yellow

Colors disabled automatically when output is piped (detect via `isatty()`).

## Error Handling

### Database Access Errors

| Scenario | Behavior |
|---|---|
| Database not found | Error: `NoteStore.sqlite not found at <path>. Is Apple Notes installed?` |
| Permission denied | Error: `Cannot access NoteStore.sqlite. Grant Full Disk Access in System Settings > Privacy & Security.` |
| Database locked | Retry 3 times with 100ms delay, then error: `Database is locked. Close Notes.app and retry.` |
| WAL checkpoint | Run `PRAGMA wal_checkpoint(PASSIVE)` before reads for fresh data |

### Note Body Edge Cases

| Scenario | Behavior |
|---|---|
| Password-protected note | Skip with warning: `Note "X" is encrypted — cannot read` |
| Note with attachments | Show `[Image: filename.jpg]` or `[Attachment: file.pdf]` placeholders |
| Empty note body | Show `(empty note)` |
| Corrupted protobuf | Error: `Cannot decode note body for "X" — data may be corrupted` |
| Tables/drawings | Show `[Table]` or `[Drawing]` placeholders (CRDT mergeabledata is out of scope) |

### Write Safety

| Scenario | Behavior |
|---|---|
| First write ever | One-time warning about direct SQLite writes being unsupported by Apple |
| Notes.app is open | Warning: `Notes.app is running. Changes may conflict with sync. Continue? [y/N]` |
| iCloud-synced account | Warning on first write about potential sync conflicts |
| `--dry-run` flag | Print what would change without writing |

### Confirmation Prompts

Destructive operations prompt for confirmation (bypassed with `--force`):

- `corenote delete` — "Delete X? This moves it to Recently Deleted. [y/N]"
- `corenote delete --permanent` — "PERMANENTLY delete X? This cannot be undone. [y/N]"
- `corenote folder delete` — "Delete folder X and all its notes? [y/N]"

## Out of Scope

- Apple Notes attachments (images, PDFs, drawings) — shown as placeholders only
- CRDT/mergeable data (tables, drawings) — shown as placeholders only
- iCloud sync management
- Password-protected note decryption
- macOS versions before Sequoia (15)
- GUI or TUI interface
