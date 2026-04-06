# Schema Compatibility Layer Design

## Problem

corenote hardcodes ~20 column names from Apple Notes' CoreData-backed SQLite database. Column names change across macOS versions (e.g., `ZISINTRASHEDBYUSER` missing on some versions). Any missing column crashes the tool with an unhelpful SQL error.

## Solution

Expand `SchemaMapper` to detect all column availability at init time via `PRAGMA table_info`. Categorize columns as **required** (fail fast if missing) or **optional** (graceful fallback). Update all queries in `NoteStoreDB` to adapt based on detected schema.

## Column Classification

### Required Columns (fail fast with clear error if missing)

These are fundamental to CoreData and Apple Notes' schema:

**ZICCLOUDSYNCINGOBJECT**: `Z_PK`, `Z_ENT`, `ZTITLE1`, `ZTITLE2`, `ZIDENTIFIER`, `ZFOLDER`, `ZNOTEDATA`, `ZCREATIONDATE1`, `ZMODIFICATIONDATE1`

**ZICNOTEDATA**: `Z_PK`, `ZDATA`, `ZNOTE`

**Z_PRIMARYKEY**: `Z_ENT`, `Z_NAME`

### Optional Columns (graceful fallback)

| Column | Table | Fallback |
|--------|-------|----------|
| `ZISINTRASHEDBYUSER` | ZICCLOUDSYNCINGOBJECT | Check folder name = "Recently Deleted" |
| `ZISPASSWORDPROTECTED` | ZICCLOUDSYNCINGOBJECT | Treat all notes as unprotected |
| `ZMARKEDFORDELETION` | ZICCLOUDSYNCINGOBJECT | Omit filter (rely on trash column or folder check) |
| `ZFOLDERTYPE` | ZICCLOUDSYNCINGOBJECT | Match folder name "Recently Deleted" instead |
| `ZSNIPPET` | ZICCLOUDSYNCINGOBJECT | Empty string |
| `ZACCOUNT2` | ZICCLOUDSYNCINGOBJECT | Omit account JOIN for notes, empty account name |
| `ZACCOUNT3` | ZICCLOUDSYNCINGOBJECT | Omit account JOIN for folders, empty account name |
| `ZPARENT` | ZICCLOUDSYNCINGOBJECT | Flat folder list, no nesting |
| `ZNAME` | ZICCLOUDSYNCINGOBJECT | Empty account name |

## Architecture Changes

### SchemaMapper (expanded)

```
SchemaMapper
  - noteEnt, folderEnt, accountEnt (existing)
  - mainTableColumns: Set<String>       // detected from PRAGMA
  - noteDataColumns: Set<String>        // detected from PRAGMA
  - func has(_ column: String) -> Bool  // check main table
  - func hasNoteData(_ column: String) -> Bool  // check note data table
  - func require(_ columns: [String]) throws   // validate required cols at init
```

### NoteStoreDB (adapted queries)

All SQL queries built dynamically using helper methods:
- `optionalSelect(alias, column, fallback)` — include column in SELECT or use fallback value
- `optionalFilter(alias, column, op, negate)` — include WHERE clause or omit
- `optionalJoin(...)` — include JOIN or omit

### Error Handling

New error type: `SchemaError.incompatibleDatabase(missing: [String])` — lists all missing required columns with a user-friendly message suggesting they may need a different corenote version for their macOS.

## Files Changed

- `Sources/corenote/Database/SchemaMapper.swift` — expand with column detection
- `Sources/corenote/Database/NoteStoreDB.swift` — adapt all queries
- `Tests/corenoteTests/SchemaMapperTests.swift` — test column detection, required validation
- `Tests/corenoteTests/NoteStoreDBTests.swift` — new file, test query adaptation with mock schemas

## Non-Goals

- Supporting macOS < 15 (we require 15+, but schema can still vary within 15.x)
- Supporting non-Apple Notes databases
- Full CoreData schema introspection
