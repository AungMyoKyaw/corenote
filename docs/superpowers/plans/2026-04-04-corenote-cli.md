# corenote CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Swift CLI tool that reads and writes Apple Notes via direct NoteStore.sqlite access, with Markdown conversion, fuzzy matching, and rich terminal output.

**Architecture:** SPM-based CLI using swift-argument-parser for commands, system libsqlite3 for database access, swift-protobuf for note body encoding/decoding. Layered: CLI -> Output -> Core Services -> Data Access -> SQLite.

**Tech Stack:** Swift 5.9+, SPM, swift-argument-parser, swift-protobuf, system libsqlite3, system Compression framework.

**Spec:** `docs/superpowers/specs/2026-04-04-corenote-cli-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `Package.swift` | SPM manifest with dependencies |
| `Sources/corenote/CoreNote.swift` | Root `@main` command, global options |
| `Sources/corenote/Database/SQLiteConnection.swift` | Thin wrapper around libsqlite3 C API |
| `Sources/corenote/Database/SchemaMapper.swift` | Discovers Z_ENT values from Z_PRIMARYKEY |
| `Sources/corenote/Database/NoteStoreDB.swift` | All queries against NoteStore schema |
| `Sources/corenote/Models/Note.swift` | Note model struct |
| `Sources/corenote/Models/Folder.swift` | Folder model struct |
| `Sources/corenote/Models/Account.swift` | Account model struct |
| `Sources/corenote/Protobuf/notestore.proto` | Reverse-engineered protobuf schema |
| `Sources/corenote/Protobuf/NoteBodyDecoder.swift` | gzip decompress + protobuf decode |
| `Sources/corenote/Protobuf/NoteBodyEncoder.swift` | protobuf encode + gzip compress |
| `Sources/corenote/Converter/NoteToMarkdown.swift` | AttributeRuns -> Markdown string |
| `Sources/corenote/Converter/MarkdownToNote.swift` | Markdown string -> text + AttributeRuns |
| `Sources/corenote/Output/Formatter.swift` | Rich terminal tables, colors, layout |
| `Sources/corenote/Output/JSONOutput.swift` | JSON serialization for --json flag |
| `Sources/corenote/Utilities/FuzzyMatcher.swift` | Title resolution with fuzzy matching |
| `Sources/corenote/Utilities/EditorLauncher.swift` | $EDITOR temp file workflow |
| `Sources/corenote/Commands/ListCommand.swift` | `corenote list` |
| `Sources/corenote/Commands/ShowCommand.swift` | `corenote show <query>` |
| `Sources/corenote/Commands/CreateCommand.swift` | `corenote create` |
| `Sources/corenote/Commands/EditCommand.swift` | `corenote edit <query>` |
| `Sources/corenote/Commands/DeleteCommand.swift` | `corenote delete <query>` |
| `Sources/corenote/Commands/SearchCommand.swift` | `corenote search <text>` |
| `Sources/corenote/Commands/MoveCommand.swift` | `corenote move <query>` |
| `Sources/corenote/Commands/Folder/FolderGroup.swift` | `corenote folder` subcommand group |
| `Sources/corenote/Commands/Folder/FolderListCommand.swift` | `corenote folder list` |
| `Sources/corenote/Commands/Folder/FolderCreateCommand.swift` | `corenote folder create` |
| `Sources/corenote/Commands/Folder/FolderRenameCommand.swift` | `corenote folder rename` |
| `Sources/corenote/Commands/Folder/FolderDeleteCommand.swift` | `corenote folder delete` |
| `Tests/corenoteTests/SQLiteConnectionTests.swift` | SQLite wrapper tests with in-memory DB |
| `Tests/corenoteTests/NoteBodyDecoderTests.swift` | Protobuf decode tests |
| `Tests/corenoteTests/NoteBodyEncoderTests.swift` | Protobuf encode tests |
| `Tests/corenoteTests/NoteToMarkdownTests.swift` | Note -> Markdown conversion tests |
| `Tests/corenoteTests/MarkdownToNoteTests.swift` | Markdown -> Note conversion tests |
| `Tests/corenoteTests/FuzzyMatcherTests.swift` | Fuzzy matching tests |
| `Tests/corenoteTests/SchemaMapperTests.swift` | Schema discovery tests |
| `Tests/corenoteTests/FormatterTests.swift` | Output formatting tests |

---

## Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Delete: `corenote/main.swift`, `corenote.xcodeproj/` (Xcode project)
- Create: `Sources/corenote/CoreNote.swift`

- [ ] **Step 1: Remove old Xcode project and create SPM structure**

```bash
rm -rf corenote.xcodeproj corenote
mkdir -p Sources/corenote Tests/corenoteTests
```

- [ ] **Step 2: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "corenote",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .executableTarget(
            name: "corenote",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "corenoteTests",
            dependencies: ["corenote"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
```

- [ ] **Step 3: Create root command**

Create `Sources/corenote/CoreNote.swift`:

```swift
import ArgumentParser

@main
struct CoreNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "corenote",
        abstract: "CLI frontend to Apple Notes",
        version: "0.1.0",
        subcommands: []
    )
}
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: Build succeeds, produces `corenote` binary.

- [ ] **Step 5: Verify help output**

Run: `.build/debug/corenote --help`
Expected: Shows "CLI frontend to Apple Notes" and version.

- [ ] **Step 6: Update .gitignore and commit**

Add to `.gitignore`:
```
.build/
.swiftpm/
```

These are already present — verify, then commit.

```bash
git add Package.swift Sources/corenote/CoreNote.swift
git rm -r corenote/main.swift corenote.xcodeproj
git commit -m "refactor: migrate from Xcode project to SPM with swift-argument-parser"
```

---

## Task 2: SQLite Connection Wrapper

**Files:**
- Create: `Sources/corenote/Database/SQLiteConnection.swift`
- Create: `Tests/corenoteTests/SQLiteConnectionTests.swift`

- [ ] **Step 1: Write failing tests for SQLiteConnection**

Create `Tests/corenoteTests/SQLiteConnectionTests.swift`:

```swift
import XCTest
@testable import corenote

final class SQLiteConnectionTests: XCTestCase {
    func testOpenInMemoryDatabase() throws {
        let db = try SQLiteConnection(path: ":memory:")
        db.close()
    }

    func testExecuteCreateTable() throws {
        let db = try SQLiteConnection(path: ":memory:")
        defer { db.close() }
        try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
    }

    func testQueryReturnsRows() throws {
        let db = try SQLiteConnection(path: ":memory:")
        defer { db.close() }
        try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO test (id, name) VALUES (1, 'hello')")
        try db.execute("INSERT INTO test (id, name) VALUES (2, 'world')")

        let rows = try db.query("SELECT id, name FROM test ORDER BY id")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["id"] as? Int64, 1)
        XCTAssertEqual(rows[0]["name"] as? String, "hello")
        XCTAssertEqual(rows[1]["id"] as? Int64, 2)
        XCTAssertEqual(rows[1]["name"] as? String, "world")
    }

    func testQueryWithParameters() throws {
        let db = try SQLiteConnection(path: ":memory:")
        defer { db.close() }
        try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO test (id, name) VALUES (1, 'hello')")
        try db.execute("INSERT INTO test (id, name) VALUES (2, 'world')")

        let rows = try db.query("SELECT name FROM test WHERE id = ?", params: [.int(1)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"] as? String, "hello")
    }

    func testQueryReturnsBlob() throws {
        let db = try SQLiteConnection(path: ":memory:")
        defer { db.close() }
        try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, data BLOB)")
        let testData = Data([0x1F, 0x8B, 0x08])
        try db.execute("INSERT INTO test (id, data) VALUES (1, ?)", params: [.blob(testData)])

        let rows = try db.query("SELECT data FROM test WHERE id = 1")
        XCTAssertEqual(rows[0]["data"] as? Data, testData)
    }

    func testOpenNonexistentFileThrows() {
        XCTAssertThrowsError(try SQLiteConnection(path: "/nonexistent/path/db.sqlite"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SQLiteConnectionTests 2>&1 | tail -5`
Expected: Compilation error — `SQLiteConnection` not defined.

- [ ] **Step 3: Implement SQLiteConnection**

Create `Sources/corenote/Database/SQLiteConnection.swift`:

```swift
import Foundation
import SQLite3

enum SQLiteParam {
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

enum SQLiteError: Error, LocalizedError {
    case openFailed(path: String, message: String)
    case executeFailed(sql: String, message: String)
    case queryFailed(sql: String, message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let message):
            return "Failed to open database at \(path): \(message)"
        case .executeFailed(let sql, let message):
            return "SQL execute failed (\(sql)): \(message)"
        case .queryFailed(let sql, let message):
            return "SQL query failed (\(sql)): \(message)"
        }
    }
}

final class SQLiteConnection {
    private var db: OpaquePointer?

    init(path: String) throws {
        let flags: Int32
        if path == ":memory:" {
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        } else {
            flags = SQLITE_OPEN_READWRITE
        }

        let result = sqlite3_open_v2(path, &db, flags, nil)
        if result != SQLITE_OK {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw SQLiteError.openFailed(path: path, message: message)
        }
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
        }
        db = nil
    }

    func execute(_ sql: String, params: [SQLiteParam] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.executeFailed(sql: sql, message: message)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt: stmt!, params: params)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE && result != SQLITE_ROW {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.executeFailed(sql: sql, message: message)
        }
    }

    func query(_ sql: String, params: [SQLiteParam] = []) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.queryFailed(sql: sql, message: message)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt: stmt!, params: params)

        var rows: [[String: Any]] = []
        let columnCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)

                switch type {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    let bytes = sqlite3_column_blob(stmt, i)
                    let count = sqlite3_column_bytes(stmt, i)
                    if let bytes = bytes {
                        row[name] = Data(bytes: bytes, count: Int(count))
                    } else {
                        row[name] = Data()
                    }
                case SQLITE_NULL:
                    break
                default:
                    break
                }
            }
            rows.append(row)
        }

        return rows
    }

    private func bindParams(stmt: OpaquePointer, params: [SQLiteParam]) throws {
        for (index, param) in params.enumerated() {
            let position = Int32(index + 1)
            var result: Int32

            switch param {
            case .int(let value):
                result = sqlite3_bind_int64(stmt, position, value)
            case .double(let value):
                result = sqlite3_bind_double(stmt, position, value)
            case .text(let value):
                result = sqlite3_bind_text(stmt, position, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .blob(let value):
                result = value.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, position, ptr.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case .null:
                result = sqlite3_bind_null(stmt, position)
            }

            if result != SQLITE_OK {
                throw SQLiteError.executeFailed(sql: "bind param \(index)", message: "bind failed")
            }
        }
    }

    deinit {
        close()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SQLiteConnectionTests 2>&1 | tail -5`
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Database/SQLiteConnection.swift Tests/corenoteTests/SQLiteConnectionTests.swift
git commit -m "feat: add SQLite connection wrapper with parameterized queries"
```

---

## Task 3: Schema Mapper

**Files:**
- Create: `Sources/corenote/Database/SchemaMapper.swift`
- Create: `Tests/corenoteTests/SchemaMapperTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/corenoteTests/SchemaMapperTests.swift`:

```swift
import XCTest
@testable import corenote

final class SchemaMapperTests: XCTestCase {
    private func createTestDB() throws -> SQLiteConnection {
        let db = try SQLiteConnection(path: ":memory:")
        try db.execute("""
            CREATE TABLE Z_PRIMARYKEY (
                Z_ENT INTEGER PRIMARY KEY,
                Z_NAME TEXT,
                Z_SUPER INTEGER,
                Z_MAX INTEGER
            )
        """)
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (6, 'ICAccount')")
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (9, 'ICFolder')")
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (14, 'ICNote')")
        return db
    }

    func testDiscoverEntityTypes() throws {
        let db = try createTestDB()
        defer { db.close() }

        let mapper = try SchemaMapper(db: db)
        XCTAssertEqual(mapper.noteEnt, 14)
        XCTAssertEqual(mapper.folderEnt, 9)
        XCTAssertEqual(mapper.accountEnt, 6)
    }

    func testThrowsWhenEntityMissing() throws {
        let db = try SQLiteConnection(path: ":memory:")
        defer { db.close() }
        try db.execute("""
            CREATE TABLE Z_PRIMARYKEY (
                Z_ENT INTEGER PRIMARY KEY,
                Z_NAME TEXT
            )
        """)
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (6, 'ICAccount')")

        XCTAssertThrowsError(try SchemaMapper(db: db))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SchemaMapperTests 2>&1 | tail -5`
Expected: Compilation error — `SchemaMapper` not defined.

- [ ] **Step 3: Implement SchemaMapper**

Create `Sources/corenote/Database/SchemaMapper.swift`:

```swift
import Foundation

enum SchemaError: Error, LocalizedError {
    case missingEntity(String)

    var errorDescription: String? {
        switch self {
        case .missingEntity(let name):
            return "Required entity '\(name)' not found in Z_PRIMARYKEY. Database may be incompatible."
        }
    }
}

struct SchemaMapper {
    let noteEnt: Int64
    let folderEnt: Int64
    let accountEnt: Int64

    init(db: SQLiteConnection) throws {
        let rows = try db.query(
            "SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY WHERE Z_NAME IN ('ICNote', 'ICFolder', 'ICAccount')"
        )

        var noteEnt: Int64?
        var folderEnt: Int64?
        var accountEnt: Int64?

        for row in rows {
            guard let name = row["Z_NAME"] as? String,
                  let ent = row["Z_ENT"] as? Int64 else { continue }
            switch name {
            case "ICNote": noteEnt = ent
            case "ICFolder": folderEnt = ent
            case "ICAccount": accountEnt = ent
            default: break
            }
        }

        guard let n = noteEnt else { throw SchemaError.missingEntity("ICNote") }
        guard let f = folderEnt else { throw SchemaError.missingEntity("ICFolder") }
        guard let a = accountEnt else { throw SchemaError.missingEntity("ICAccount") }

        self.noteEnt = n
        self.folderEnt = f
        self.accountEnt = a
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SchemaMapperTests 2>&1 | tail -5`
Expected: All 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Database/SchemaMapper.swift Tests/corenoteTests/SchemaMapperTests.swift
git commit -m "feat: add SchemaMapper to discover Z_ENT values from Z_PRIMARYKEY"
```

---

## Task 4: Models

**Files:**
- Create: `Sources/corenote/Models/Note.swift`
- Create: `Sources/corenote/Models/Folder.swift`
- Create: `Sources/corenote/Models/Account.swift`

- [ ] **Step 1: Create Note model**

Create `Sources/corenote/Models/Note.swift`:

```swift
import Foundation

struct Note {
    let pk: Int64
    let uuid: String
    let title: String
    let snippet: String
    let folderName: String
    let accountName: String
    let createdAt: Date
    let modifiedAt: Date
    let isTrashed: Bool
    let isPasswordProtected: Bool
    let bodyData: Data?

    static let macEpochOffset: TimeInterval = 978307200

    static func dateFromMac(_ macTime: Double) -> Date {
        Date(timeIntervalSince1970: macTime + macEpochOffset)
    }

    static func macFromDate(_ date: Date) -> Double {
        date.timeIntervalSince1970 - macEpochOffset
    }
}
```

- [ ] **Step 2: Create Folder model**

Create `Sources/corenote/Models/Folder.swift`:

```swift
import Foundation

struct Folder {
    let pk: Int64
    let uuid: String
    let name: String
    let accountName: String
    let parentPK: Int64?
    let noteCount: Int
}
```

- [ ] **Step 3: Create Account model**

Create `Sources/corenote/Models/Account.swift`:

```swift
import Foundation

struct Account {
    let pk: Int64
    let name: String
    let type: Int64
}
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Models/
git commit -m "feat: add Note, Folder, Account model structs"
```

---

## Task 5: NoteStoreDB Read Queries

**Files:**
- Create: `Sources/corenote/Database/NoteStoreDB.swift`

- [ ] **Step 1: Implement NoteStoreDB with read queries**

Create `Sources/corenote/Database/NoteStoreDB.swift`:

```swift
import Foundation

enum NoteStoreError: Error, LocalizedError {
    case databaseNotFound(path: String)
    case noteNotFound(query: String)
    case folderNotFound(name: String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path):
            return "NoteStore.sqlite not found at \(path). Is Apple Notes installed?"
        case .noteNotFound(let query):
            return "No note found matching \"\(query)\""
        case .folderNotFound(let name):
            return "No folder found matching \"\(name)\""
        }
    }
}

final class NoteStoreDB {
    static let defaultPath = NSHomeDirectory() +
        "/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"

    let db: SQLiteConnection
    let schema: SchemaMapper

    init(path: String? = nil) throws {
        let dbPath = path ?? Self.defaultPath
        guard FileManager.default.fileExists(atPath: dbPath) || path != nil else {
            throw NoteStoreError.databaseNotFound(path: dbPath)
        }
        self.db = try SQLiteConnection(path: dbPath)
        try db.execute("PRAGMA wal_checkpoint(PASSIVE)")
        self.schema = try SchemaMapper(db: db)
    }

    func listNotes(folder: String? = nil, account: String? = nil,
                   limit: Int = 50, sort: String = "modified") throws -> [Note] {
        var sql = """
            SELECT c.Z_PK, c.ZTITLE1, c.ZSNIPPET, c.ZIDENTIFIER,
                   c.ZCREATIONDATE1, c.ZMODIFICATIONDATE1,
                   c.ZISINTRASHEDBYUSER, c.ZISPASSWORDPROTECTED,
                   f.ZTITLE2 as folder_name, a.ZNAME as account_name
            FROM ZICCLOUDSYNCINGOBJECT c
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON f.Z_PK = c.ZFOLDER
            LEFT JOIN ZICCLOUDSYNCINGOBJECT a ON a.Z_PK = c.ZACCOUNT2
            WHERE c.Z_ENT = ?
              AND (c.ZMARKEDFORDELETION != 1 OR c.ZMARKEDFORDELETION IS NULL)
              AND (c.ZISINTRASHEDBYUSER != 1 OR c.ZISINTRASHEDBYUSER IS NULL)
        """
        var params: [SQLiteParam] = [.int(schema.noteEnt)]

        if let folder = folder {
            sql += " AND f.ZTITLE2 = ?"
            params.append(.text(folder))
        }
        if let account = account {
            sql += " AND a.ZNAME = ?"
            params.append(.text(account))
        }

        switch sort {
        case "created": sql += " ORDER BY c.ZCREATIONDATE1 DESC"
        case "title": sql += " ORDER BY c.ZTITLE1 ASC"
        default: sql += " ORDER BY c.ZMODIFICATIONDATE1 DESC"
        }

        sql += " LIMIT ?"
        params.append(.int(Int64(limit)))

        let rows = try db.query(sql, params: params)
        return rows.compactMap { noteFromRow($0) }
    }

    func getNoteBody(notePK: Int64) throws -> Data? {
        let rows = try db.query(
            "SELECT n.ZDATA FROM ZICNOTEDATA n JOIN ZICCLOUDSYNCINGOBJECT c ON c.ZNOTEDATA = n.Z_PK WHERE c.Z_PK = ?",
            params: [.int(notePK)]
        )
        return rows.first?["ZDATA"] as? Data
    }

    func searchNotes(text: String, folder: String? = nil, limit: Int = 50) throws -> [Note] {
        var sql = """
            SELECT c.Z_PK, c.ZTITLE1, c.ZSNIPPET, c.ZIDENTIFIER,
                   c.ZCREATIONDATE1, c.ZMODIFICATIONDATE1,
                   c.ZISINTRASHEDBYUSER, c.ZISPASSWORDPROTECTED,
                   f.ZTITLE2 as folder_name, a.ZNAME as account_name
            FROM ZICCLOUDSYNCINGOBJECT c
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON f.Z_PK = c.ZFOLDER
            LEFT JOIN ZICCLOUDSYNCINGOBJECT a ON a.Z_PK = c.ZACCOUNT2
            LEFT JOIN ZICNOTEDATA n ON c.ZNOTEDATA = n.Z_PK
            WHERE c.Z_ENT = ?
              AND (c.ZMARKEDFORDELETION != 1 OR c.ZMARKEDFORDELETION IS NULL)
              AND (c.ZISINTRASHEDBYUSER != 1 OR c.ZISINTRASHEDBYUSER IS NULL)
              AND (c.ZTITLE1 LIKE ? OR c.ZSNIPPET LIKE ?)
        """
        let pattern = "%\(text)%"
        var params: [SQLiteParam] = [.int(schema.noteEnt), .text(pattern), .text(pattern)]

        if let folder = folder {
            sql += " AND f.ZTITLE2 = ?"
            params.append(.text(folder))
        }

        sql += " ORDER BY c.ZMODIFICATIONDATE1 DESC LIMIT ?"
        params.append(.int(Int64(limit)))

        let rows = try db.query(sql, params: params)
        return rows.compactMap { noteFromRow($0) }
    }

    func listFolders(account: String? = nil) throws -> [Folder] {
        var sql = """
            SELECT f.Z_PK, f.ZTITLE2, f.ZIDENTIFIER, f.ZPARENT,
                   a.ZNAME as account_name,
                   (SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT n
                    WHERE n.ZFOLDER = f.Z_PK AND n.Z_ENT = ?
                    AND (n.ZMARKEDFORDELETION != 1 OR n.ZMARKEDFORDELETION IS NULL)
                    AND (n.ZISINTRASHEDBYUSER != 1 OR n.ZISINTRASHEDBYUSER IS NULL)
                   ) as note_count
            FROM ZICCLOUDSYNCINGOBJECT f
            LEFT JOIN ZICCLOUDSYNCINGOBJECT a ON a.Z_PK = f.ZACCOUNT3
            WHERE f.Z_ENT = ?
        """
        var params: [SQLiteParam] = [.int(schema.noteEnt), .int(schema.folderEnt)]

        if let account = account {
            sql += " AND a.ZNAME = ?"
            params.append(.text(account))
        }
        sql += " ORDER BY f.ZTITLE2 ASC"

        let rows = try db.query(sql, params: params)
        return rows.compactMap { folderFromRow($0) }
    }

    func findNotePK(byUUID uuid: String) throws -> Int64? {
        let rows = try db.query(
            "SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = ? AND Z_ENT = ?",
            params: [.text(uuid), .int(schema.noteEnt)]
        )
        return rows.first?["Z_PK"] as? Int64
    }

    func findFolderPK(byName name: String) throws -> Int64? {
        let rows = try db.query(
            "SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE ZTITLE2 = ? AND Z_ENT = ?",
            params: [.text(name), .int(schema.folderEnt)]
        )
        return rows.first?["Z_PK"] as? Int64
    }

    func isNotesAppRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "Notes"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // MARK: - Row mapping

    private func noteFromRow(_ row: [String: Any]) -> Note? {
        guard let pk = row["Z_PK"] as? Int64,
              let uuid = row["ZIDENTIFIER"] as? String else { return nil }

        let title = row["ZTITLE1"] as? String ?? "(untitled)"
        let snippet = row["ZSNIPPET"] as? String ?? ""
        let folderName = row["folder_name"] as? String ?? ""
        let accountName = row["account_name"] as? String ?? ""
        let createdMac = row["ZCREATIONDATE1"] as? Double ?? 0
        let modifiedMac = row["ZMODIFICATIONDATE1"] as? Double ?? 0
        let isTrashed = (row["ZISINTRASHEDBYUSER"] as? Int64 ?? 0) == 1
        let isProtected = (row["ZISPASSWORDPROTECTED"] as? Int64 ?? 0) == 1

        return Note(
            pk: pk, uuid: uuid, title: title, snippet: snippet,
            folderName: folderName, accountName: accountName,
            createdAt: Note.dateFromMac(createdMac),
            modifiedAt: Note.dateFromMac(modifiedMac),
            isTrashed: isTrashed, isPasswordProtected: isProtected,
            bodyData: nil
        )
    }

    private func folderFromRow(_ row: [String: Any]) -> Folder? {
        guard let pk = row["Z_PK"] as? Int64,
              let uuid = row["ZIDENTIFIER"] as? String else { return nil }

        return Folder(
            pk: pk, uuid: uuid,
            name: row["ZTITLE2"] as? String ?? "(unnamed)",
            accountName: row["account_name"] as? String ?? "",
            parentPK: row["ZPARENT"] as? Int64,
            noteCount: Int(row["note_count"] as? Int64 ?? 0)
        )
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/corenote/Database/NoteStoreDB.swift
git commit -m "feat: add NoteStoreDB with read queries for notes, folders, search"
```

---

## Task 6: Protobuf Schema and Code Generation

**Files:**
- Create: `Sources/corenote/Protobuf/notestore.proto`
- Generate: `Sources/corenote/Protobuf/notestore.pb.swift` (generated from proto)

- [ ] **Step 1: Create the reverse-engineered proto schema**

Create `Sources/corenote/Protobuf/notestore.proto`:

```protobuf
syntax = "proto2";

option swift_prefix = "CN";

message NoteStoreProto {
    optional Document document = 2;
}

message Document {
    optional int32 version = 2;
    optional Note note = 3;
}

message Note {
    optional string note_text = 2;
    repeated AttributeRun attribute_run = 5;
}

message AttributeRun {
    optional int32 length = 1;
    optional ParagraphStyle paragraph_style = 2;
    optional Font font = 3;
    optional int32 font_weight = 5;
    optional int32 underlined = 6;
    optional int32 strikethrough = 7;
    optional int32 superscript = 8;
    optional string link = 9;
    optional Color color = 10;
    optional AttachmentInfo attachment_info = 12;
}

message ParagraphStyle {
    optional int32 style_type = 1;
    optional int32 alignment = 2;
    optional int32 indent_amount = 4;
    optional Checklist checklist = 5;
    optional int32 list_style = 6;
    optional int32 blockquote = 9;
}

message Checklist {
    optional bytes uuid = 1;
    optional int32 done = 2;
}

message Font {
    optional string name = 1;
    optional float point_size = 2;
    optional int32 font_hints = 3;
}

message Color {
    optional float red = 1;
    optional float green = 2;
    optional float blue = 3;
    optional float alpha = 4;
}

message AttachmentInfo {
    optional string attachment_identifier = 1;
    optional string type_uti = 2;
}
```

- [ ] **Step 2: Install protoc and swift-protobuf plugin if needed**

Run: `which protoc && which protoc-gen-swift`

If not installed:
```bash
brew install protobuf swift-protobuf
```

- [ ] **Step 3: Generate Swift code from proto**

```bash
protoc --swift_out=Sources/corenote/Protobuf/ \
       --swift_opt=Visibility=Internal \
       Sources/corenote/Protobuf/notestore.proto
```

This generates `Sources/corenote/Protobuf/notestore.pb.swift`.

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: Build succeeds with generated protobuf types.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Protobuf/notestore.proto Sources/corenote/Protobuf/notestore.pb.swift
git commit -m "feat: add reverse-engineered Apple Notes protobuf schema with generated Swift code"
```

---

## Task 7: Note Body Decoder

**Files:**
- Create: `Sources/corenote/Protobuf/NoteBodyDecoder.swift`
- Create: `Tests/corenoteTests/NoteBodyDecoderTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/corenoteTests/NoteBodyDecoderTests.swift`:

```swift
import XCTest
import Foundation
@testable import corenote

final class NoteBodyDecoderTests: XCTestCase {
    func testDecodeUncompressedProtobuf() throws {
        // Build a minimal NoteStoreProto manually
        var note = CNNote()
        note.noteText = "Hello World"
        var run = CNAttributeRun()
        run.length = 11
        note.attributeRun = [run]

        var doc = CNDocument()
        doc.version = 0
        doc.note = note

        var proto = CNNoteStoreProto()
        proto.document = doc

        let data = try proto.serializedData()

        let decoded = try NoteBodyDecoder.decode(data: data)
        XCTAssertEqual(decoded.text, "Hello World")
        XCTAssertEqual(decoded.runs.count, 1)
        XCTAssertEqual(decoded.runs[0].length, 11)
    }

    func testDecodeGzippedProtobuf() throws {
        var note = CNNote()
        note.noteText = "Compressed note"
        var run = CNAttributeRun()
        run.length = 15
        note.attributeRun = [run]

        var doc = CNDocument()
        doc.note = note

        var proto = CNNoteStoreProto()
        proto.document = doc

        let raw = try proto.serializedData()
        let gzipped = try GzipHelper.compress(raw)

        let decoded = try NoteBodyDecoder.decode(data: gzipped)
        XCTAssertEqual(decoded.text, "Compressed note")
    }

    func testDecodeWithFormattingRuns() throws {
        var note = CNNote()
        note.noteText = "Title\nBold text"

        var titleRun = CNAttributeRun()
        titleRun.length = 6
        var titleStyle = CNParagraphStyle()
        titleStyle.styleType = 1
        titleRun.paragraphStyle = titleStyle

        var boldRun = CNAttributeRun()
        boldRun.length = 9
        boldRun.fontWeight = 1

        note.attributeRun = [titleRun, boldRun]

        var doc = CNDocument()
        doc.note = note

        var proto = CNNoteStoreProto()
        proto.document = doc

        let data = try proto.serializedData()
        let decoded = try NoteBodyDecoder.decode(data: data)

        XCTAssertEqual(decoded.runs.count, 2)
        XCTAssertEqual(decoded.runs[0].paragraphStyle?.styleType, .heading1)
        XCTAssertTrue(decoded.runs[1].isBold)
    }

    func testDecodeEncryptedDataThrows() {
        let notGzipped = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try NoteBodyDecoder.decode(data: notGzipped))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NoteBodyDecoderTests 2>&1 | tail -5`
Expected: Compilation error — `NoteBodyDecoder` not defined.

- [ ] **Step 3: Implement GzipHelper and NoteBodyDecoder**

Create `Sources/corenote/Protobuf/NoteBodyDecoder.swift`:

```swift
import Foundation
import Compression

// MARK: - Gzip Helper

enum GzipError: Error, LocalizedError {
    case compressFailed
    case decompressFailed

    var errorDescription: String? {
        switch self {
        case .compressFailed: return "Gzip compression failed"
        case .decompressFailed: return "Gzip decompression failed"
        }
    }
}

enum GzipHelper {
    static let gzipMagic: [UInt8] = [0x1F, 0x8B]

    static func isGzipped(_ data: Data) -> Bool {
        data.count >= 2 && data[0] == gzipMagic[0] && data[1] == gzipMagic[1]
    }

    static func decompress(_ data: Data) throws -> Data {
        let bufferSize = 65536
        var output = Data()

        try data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            guard let srcPtr = rawPtr.baseAddress else { throw GzipError.decompressFailed }

            let stream = compression_stream_init_with_options(
                COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB, COMPRESSION_ZLIB_GZIP_HEADER
            )
            guard let filter = stream else { throw GzipError.decompressFailed }
            defer { compression_stream_destroy(filter) }

            var status = compression_stream_process(filter, srcPtr, data.count)

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            repeat {
                status = compression_stream_process(filter, nil, 0)
                let have = compression_stream_get_output_size(filter)
                if have > 0 {
                    let read = compression_stream_read_output(filter, buffer, min(have, bufferSize))
                    output.append(buffer, count: read)
                }
            } while status == COMPRESSION_STATUS_OK

            if status != COMPRESSION_STATUS_END {
                throw GzipError.decompressFailed
            }
        }

        return output
    }

    static func compress(_ data: Data) throws -> Data {
        let bufferSize = 65536
        var output = Data()

        try data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            guard let srcPtr = rawPtr.baseAddress else { throw GzipError.compressFailed }

            let stream = compression_stream_init_with_options(
                COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB, COMPRESSION_ZLIB_GZIP_HEADER
            )
            guard let filter = stream else { throw GzipError.compressFailed }
            defer { compression_stream_destroy(filter) }

            var status = compression_stream_process(filter, srcPtr, data.count)

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }

            status = compression_stream_finalize(filter)

            repeat {
                let have = compression_stream_get_output_size(filter)
                if have > 0 {
                    let read = compression_stream_read_output(filter, buffer, min(have, bufferSize))
                    output.append(buffer, count: read)
                } else {
                    break
                }
            } while true
        }

        if output.isEmpty { throw GzipError.compressFailed }
        return output
    }
}

// MARK: - Decoded Note Body

struct DecodedNoteBody {
    let text: String
    let runs: [DecodedRun]
}

struct DecodedRun {
    let length: Int
    let paragraphStyle: DecodedParagraphStyle?
    let isBold: Bool
    let isUnderlined: Bool
    let isStrikethrough: Bool
    let link: String?
    let attachment: DecodedAttachment?

    struct DecodedParagraphStyle {
        enum StyleType: Int {
            case title = 0
            case heading1 = 1
            case heading2 = 2
            case heading3 = 3
        }

        let styleType: StyleType?
        let listStyle: Int?    // 100 = bullet, 200 = numbered
        let isChecklist: Bool
        let isChecklistDone: Bool
        let isBlockquote: Bool
        let indentAmount: Int
    }

    struct DecodedAttachment {
        let identifier: String
        let typeUTI: String
    }
}

// MARK: - Decoder

enum NoteBodyDecoderError: Error, LocalizedError {
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let reason):
            return "Cannot decode note body: \(reason)"
        }
    }
}

enum NoteBodyDecoder {
    static func decode(data: Data) throws -> DecodedNoteBody {
        let protoData: Data
        if GzipHelper.isGzipped(data) {
            protoData = try GzipHelper.decompress(data)
        } else {
            protoData = data
        }

        let proto: CNNoteStoreProto
        do {
            proto = try CNNoteStoreProto(serializedBytes: protoData)
        } catch {
            throw NoteBodyDecoderError.decodeFailed("protobuf parse error: \(error.localizedDescription)")
        }

        guard proto.hasDocument, proto.document.hasNote else {
            throw NoteBodyDecoderError.decodeFailed("missing document or note in protobuf")
        }

        let note = proto.document.note
        let text = note.noteText
        let runs = note.attributeRun.map { run -> DecodedRun in
            let paragraphStyle: DecodedRun.DecodedParagraphStyle?
            if run.hasParagraphStyle {
                let ps = run.paragraphStyle
                paragraphStyle = DecodedRun.DecodedParagraphStyle(
                    styleType: DecodedRun.DecodedParagraphStyle.StyleType(rawValue: Int(ps.styleType)),
                    listStyle: ps.hasListStyle ? Int(ps.listStyle) : nil,
                    isChecklist: ps.hasChecklist,
                    isChecklistDone: ps.hasChecklist && ps.checklist.done == 1,
                    isBlockquote: ps.hasBlockquote && ps.blockquote == 1,
                    indentAmount: Int(ps.indentAmount)
                )
            } else {
                paragraphStyle = nil
            }

            let attachment: DecodedRun.DecodedAttachment?
            if run.hasAttachmentInfo {
                attachment = DecodedRun.DecodedAttachment(
                    identifier: run.attachmentInfo.attachmentIdentifier,
                    typeUTI: run.attachmentInfo.typeUti
                )
            } else {
                attachment = nil
            }

            return DecodedRun(
                length: Int(run.length),
                paragraphStyle: paragraphStyle,
                isBold: run.hasFontWeight && run.fontWeight == 1,
                isUnderlined: run.hasUnderlined && run.underlined == 1,
                isStrikethrough: run.hasStrikethrough && run.strikethrough == 1,
                link: run.hasLink ? run.link : nil,
                attachment: attachment
            )
        }

        return DecodedNoteBody(text: text, runs: runs)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NoteBodyDecoderTests 2>&1 | tail -5`
Expected: All 4 tests pass.

Note: The gzip test may need adjustment depending on the exact Compression framework API available on macOS 15. If the `compression_stream_*` functions don't exist, fall back to using `NSData` with `compressed(using:)` / `decompressed(using:)` or shell out to `gunzip`. Fix the implementation to match what compiles.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Protobuf/NoteBodyDecoder.swift Tests/corenoteTests/NoteBodyDecoderTests.swift
git commit -m "feat: add NoteBodyDecoder with gzip decompression and protobuf parsing"
```

---

## Task 8: Note to Markdown Converter

**Files:**
- Create: `Sources/corenote/Converter/NoteToMarkdown.swift`
- Create: `Tests/corenoteTests/NoteToMarkdownTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/corenoteTests/NoteToMarkdownTests.swift`:

```swift
import XCTest
@testable import corenote

final class NoteToMarkdownTests: XCTestCase {
    func testPlainText() {
        let body = DecodedNoteBody(
            text: "Hello World\n",
            runs: [DecodedRun(length: 12, paragraphStyle: nil, isBold: false,
                              isUnderlined: false, isStrikethrough: false,
                              link: nil, attachment: nil)]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertEqual(md, "Hello World")
    }

    func testHeading1() {
        let body = DecodedNoteBody(
            text: "Title\nBody text\n",
            runs: [
                DecodedRun(length: 6, paragraphStyle: .init(
                    styleType: .heading1, listStyle: nil, isChecklist: false,
                    isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 10, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.hasPrefix("# Title\n"))
        XCTAssertTrue(md.contains("Body text"))
    }

    func testBoldText() {
        let body = DecodedNoteBody(
            text: "Hello Bold\n",
            runs: [
                DecodedRun(length: 6, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 5, paragraphStyle: nil, isBold: true,
                    isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("**Bold**"))
    }

    func testStrikethrough() {
        let body = DecodedNoteBody(
            text: "removed\n",
            runs: [
                DecodedRun(length: 8, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: true,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("~~removed~~"))
    }

    func testLink() {
        let body = DecodedNoteBody(
            text: "click here\n",
            runs: [
                DecodedRun(length: 11, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: false,
                    link: "https://example.com", attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("[click here](https://example.com)"))
    }

    func testBulletList() {
        let body = DecodedNoteBody(
            text: "Item 1\nItem 2\n",
            runs: [
                DecodedRun(length: 7, paragraphStyle: .init(
                    styleType: nil, listStyle: 100, isChecklist: false,
                    isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 7, paragraphStyle: .init(
                    styleType: nil, listStyle: 100, isChecklist: false,
                    isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("- Item 1"))
        XCTAssertTrue(md.contains("- Item 2"))
    }

    func testChecklist() {
        let body = DecodedNoteBody(
            text: "Done\nNot done\n",
            runs: [
                DecodedRun(length: 5, paragraphStyle: .init(
                    styleType: nil, listStyle: nil, isChecklist: true,
                    isChecklistDone: true, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 9, paragraphStyle: .init(
                    styleType: nil, listStyle: nil, isChecklist: true,
                    isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("- [x] Done"))
        XCTAssertTrue(md.contains("- [ ] Not done"))
    }

    func testAttachmentPlaceholder() {
        let body = DecodedNoteBody(
            text: "\u{FFFC}\n",
            runs: [
                DecodedRun(length: 2, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: false, link: nil,
                    attachment: .init(identifier: "abc-123", typeUTI: "public.jpeg")),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("[Image: abc-123]"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NoteToMarkdownTests 2>&1 | tail -5`
Expected: Compilation error — `NoteToMarkdown` not defined.

- [ ] **Step 3: Implement NoteToMarkdown**

Create `Sources/corenote/Converter/NoteToMarkdown.swift`:

```swift
import Foundation

enum NoteToMarkdown {
    static func convert(_ body: DecodedNoteBody) -> String {
        let text = body.text
        var result = ""
        var charIndex = text.startIndex

        for run in body.runs {
            let endIndex = text.index(charIndex, offsetBy: run.length, limitedBy: text.endIndex) ?? text.endIndex
            var segment = String(text[charIndex..<endIndex])
            charIndex = endIndex

            // Handle attachment placeholder (U+FFFC)
            if segment.contains("\u{FFFC}"), let att = run.attachment {
                let placeholder = attachmentPlaceholder(att)
                segment = segment.replacingOccurrences(of: "\u{FFFC}", with: placeholder)
                result += segment
                continue
            }

            // Remove trailing newline for per-line processing, re-add after
            let trailingNewline = segment.hasSuffix("\n")
            if trailingNewline {
                segment = String(segment.dropLast())
            }

            let lines = segment.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

            for (lineIdx, line) in lines.enumerated() {
                var processedLine = line

                // Apply inline formatting
                if run.isBold {
                    processedLine = "**\(processedLine)**"
                }
                if run.isStrikethrough {
                    processedLine = "~~\(processedLine)~~"
                }
                if let link = run.link {
                    processedLine = "[\(processedLine)](\(link))"
                }

                // Apply paragraph-level formatting
                if let ps = run.paragraphStyle {
                    if let styleType = ps.styleType {
                        switch styleType {
                        case .heading1: processedLine = "# \(processedLine)"
                        case .heading2: processedLine = "## \(processedLine)"
                        case .heading3: processedLine = "### \(processedLine)"
                        case .title: processedLine = "# \(processedLine)"
                        }
                    } else if ps.isChecklist {
                        let check = ps.isChecklistDone ? "x" : " "
                        processedLine = "- [\(check)] \(processedLine)"
                    } else if let listStyle = ps.listStyle {
                        if listStyle == 100 {
                            let indent = String(repeating: "  ", count: ps.indentAmount)
                            processedLine = "\(indent)- \(processedLine)"
                        } else if listStyle == 200 {
                            let indent = String(repeating: "  ", count: ps.indentAmount)
                            processedLine = "\(indent)1. \(processedLine)"
                        }
                    }
                    if ps.isBlockquote {
                        processedLine = "> \(processedLine)"
                    }
                }

                result += processedLine
                if lineIdx < lines.count - 1 {
                    result += "\n"
                }
            }

            if trailingNewline {
                result += "\n"
            }
        }

        // Trim trailing whitespace/newlines
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attachmentPlaceholder(_ att: DecodedRun.DecodedAttachment) -> String {
        let uti = att.typeUTI.lowercased()
        if uti.contains("image") || uti.contains("jpeg") || uti.contains("png") || uti.contains("gif") {
            return "[Image: \(att.identifier)]"
        } else if uti.contains("drawing") {
            return "[Drawing: \(att.identifier)]"
        } else {
            return "[Attachment: \(att.identifier)]"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NoteToMarkdownTests 2>&1 | tail -5`
Expected: All 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Converter/NoteToMarkdown.swift Tests/corenoteTests/NoteToMarkdownTests.swift
git commit -m "feat: add NoteToMarkdown converter with formatting, lists, checklists, attachments"
```

---

## Task 9: Fuzzy Matcher

**Files:**
- Create: `Sources/corenote/Utilities/FuzzyMatcher.swift`
- Create: `Tests/corenoteTests/FuzzyMatcherTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/corenoteTests/FuzzyMatcherTests.swift`:

```swift
import XCTest
@testable import corenote

final class FuzzyMatcherTests: XCTestCase {
    let titles = [
        "Shopping List",
        "Meeting Notes",
        "API Design Doc",
        "Travel Plans",
        "Shopping Budget",
    ]

    func testExactMatch() {
        let results = FuzzyMatcher.match(query: "Shopping List", candidates: titles)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "Shopping List")
    }

    func testExactMatchCaseInsensitive() {
        let results = FuzzyMatcher.match(query: "shopping list", candidates: titles)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "Shopping List")
    }

    func testPrefixMatch() {
        let results = FuzzyMatcher.match(query: "Shop", candidates: titles)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains("Shopping List"))
        XCTAssertTrue(results.contains("Shopping Budget"))
    }

    func testContainsMatch() {
        let results = FuzzyMatcher.match(query: "Design", candidates: titles)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "API Design Doc")
    }

    func testFuzzyMatch() {
        let results = FuzzyMatcher.match(query: "Shoping List", candidates: titles)
        XCTAssertTrue(results.contains("Shopping List"))
    }

    func testNoMatch() {
        let results = FuzzyMatcher.match(query: "Nonexistent", candidates: titles)
        XCTAssertTrue(results.isEmpty)
    }

    func testShortQuerySkipsFuzzy() {
        // 1-2 char queries only do exact/prefix, not fuzzy
        let results = FuzzyMatcher.match(query: "Sh", candidates: titles)
        XCTAssertEqual(results.count, 2) // prefix matches only
    }

    func testLevenshteinDistance() {
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("kitten", "sitting"), 3)
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("", "abc"), 3)
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("abc", "abc"), 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FuzzyMatcherTests 2>&1 | tail -5`
Expected: Compilation error — `FuzzyMatcher` not defined.

- [ ] **Step 3: Implement FuzzyMatcher**

Create `Sources/corenote/Utilities/FuzzyMatcher.swift`:

```swift
import Foundation

enum FuzzyMatcher {
    /// Returns matching candidates in priority order: exact > prefix > contains > fuzzy.
    /// Short queries (1-2 chars) skip fuzzy matching.
    static func match(query: String, candidates: [String]) -> [String] {
        let q = query.lowercased()

        // 1. Exact match
        let exact = candidates.filter { $0.lowercased() == q }
        if !exact.isEmpty { return exact }

        // 2. Prefix match
        let prefix = candidates.filter { $0.lowercased().hasPrefix(q) }
        if !prefix.isEmpty { return prefix }

        // 3. Contains match
        let contains = candidates.filter { $0.lowercased().contains(q) }
        if !contains.isEmpty { return contains }

        // 4. Fuzzy match (skip for very short queries)
        if q.count <= 2 { return [] }

        let threshold = 0.6
        var scored: [(String, Double)] = []

        for candidate in candidates {
            let distance = levenshteinDistance(q, candidate.lowercased())
            let maxLen = max(q.count, candidate.count)
            let similarity = maxLen == 0 ? 1.0 : 1.0 - Double(distance) / Double(maxLen)
            if similarity >= threshold {
                scored.append((candidate, similarity))
            }
        }

        scored.sort { $0.1 > $1.1 }
        return scored.map { $0.0 }
    }

    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,        // deletion
                    curr[j - 1] + 1,     // insertion
                    prev[j - 1] + cost   // substitution
                )
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FuzzyMatcherTests 2>&1 | tail -5`
Expected: All 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Utilities/FuzzyMatcher.swift Tests/corenoteTests/FuzzyMatcherTests.swift
git commit -m "feat: add FuzzyMatcher with exact, prefix, contains, and Levenshtein matching"
```

---

## Task 10: Output Formatter

**Files:**
- Create: `Sources/corenote/Output/Formatter.swift`
- Create: `Sources/corenote/Output/JSONOutput.swift`
- Create: `Tests/corenoteTests/FormatterTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/corenoteTests/FormatterTests.swift`:

```swift
import XCTest
@testable import corenote

final class FormatterTests: XCTestCase {
    func testRelativeDate() {
        let now = Date()
        XCTAssertEqual(OutputFormatter.relativeDate(now), "just now")

        let fiveMinAgo = now.addingTimeInterval(-300)
        XCTAssertEqual(OutputFormatter.relativeDate(fiveMinAgo), "5 minutes ago")

        let twoHoursAgo = now.addingTimeInterval(-7200)
        XCTAssertEqual(OutputFormatter.relativeDate(twoHoursAgo), "2 hours ago")

        let yesterday = now.addingTimeInterval(-86400)
        XCTAssertEqual(OutputFormatter.relativeDate(yesterday), "Yesterday")
    }

    func testColorDisabledReturnsPlainText() {
        let result = OutputFormatter.colored("hello", .cyan, forceColor: false)
        XCTAssertEqual(result, "hello")
    }

    func testColorEnabledReturnsANSI() {
        let result = OutputFormatter.colored("hello", .cyan, forceColor: true)
        XCTAssertTrue(result.contains("\u{1B}["))
        XCTAssertTrue(result.contains("hello"))
    }

    func testPadRight() {
        XCTAssertEqual(OutputFormatter.padRight("hi", width: 5), "hi   ")
        XCTAssertEqual(OutputFormatter.padRight("hello", width: 3), "hello")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FormatterTests 2>&1 | tail -5`
Expected: Compilation error — `OutputFormatter` not defined.

- [ ] **Step 3: Implement OutputFormatter**

Create `Sources/corenote/Output/Formatter.swift`:

```swift
import Foundation

enum ANSIColor: String {
    case red = "\u{1B}[31m"
    case green = "\u{1B}[32m"
    case yellow = "\u{1B}[33m"
    case cyan = "\u{1B}[36m"
    case white = "\u{1B}[1;37m"
    case dim = "\u{1B}[2m"
    case reset = "\u{1B}[0m"
    case bold = "\u{1B}[1m"
}

enum OutputFormatter {
    static var isInteractive: Bool {
        isatty(fileno(stdout)) != 0
    }

    static func colored(_ text: String, _ color: ANSIColor, forceColor: Bool? = nil) -> String {
        let useColor = forceColor ?? isInteractive
        guard useColor else { return text }
        return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }

    static func bold(_ text: String) -> String {
        colored(text, .bold)
    }

    static func relativeDate(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 {
            let mins = seconds / 60
            return "\(mins) minute\(mins == 1 ? "" : "s") ago"
        }
        if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
        if seconds < 172800 { return "Yesterday" }
        if seconds < 604800 {
            let days = seconds / 86400
            return "\(days) days ago"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    static func padRight(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return text + String(repeating: " ", count: width - text.count)
    }

    static func formatNoteList(_ notes: [Note]) -> String {
        var output = ""
        let header = " \(padRight("#", width: 4))\(padRight("Title", width: 25))\(padRight("Modified", width: 18))Folder"
        output += colored(header, .dim) + "\n"

        for (i, note) in notes.enumerated() {
            let num = padRight("\(i + 1)", width: 4)
            let title = padRight(String(note.title.prefix(23)), width: 25)
            let modified = padRight(relativeDate(note.modifiedAt), width: 18)
            let folder = colored(note.folderName, .cyan)
            output += " \(num)\(colored(title, .white))  \(colored(modified, .yellow))  \(folder)\n"
        }

        let summary = "\n\(notes.count) note\(notes.count == 1 ? "" : "s")"
        output += colored(summary, .dim)
        return output
    }

    static func formatNoteDetail(note: Note, body: String) -> String {
        var output = ""
        output += "\n\(colored(note.title, .white))\n"
        output += colored(String(repeating: "\u{2550}", count: 40), .dim) + "\n"

        let meta = [
            "\(colored("Folder:", .dim)) \(colored(note.folderName, .cyan))",
            "\(colored("Modified:", .dim)) \(colored(relativeDate(note.modifiedAt), .yellow))",
            "\(colored("Created:", .dim)) \(colored(relativeDate(note.createdAt), .yellow))",
        ].joined(separator: "  \(colored("\u{2502}", .dim))  ")
        output += meta + "\n\n"
        output += body + "\n"
        return output
    }

    static func formatFolderList(_ folders: [Folder]) -> String {
        var output = ""
        let header = " \(padRight("Folder", width: 20))\(padRight("Notes", width: 8))Account"
        output += colored(header, .dim) + "\n"

        for folder in folders {
            let name = padRight(String(folder.name.prefix(18)), width: 20)
            let count = padRight("\(folder.noteCount)", width: 8)
            output += " \(colored(name, .cyan))\(count)\(folder.accountName)\n"
        }

        return output
    }

    static func formatSearchResults(_ notes: [Note], query: String) -> String {
        var output = ""
        let header = " \(padRight("#", width: 4))\(padRight("Title", width: 20))\(padRight("Folder", width: 14))Match"
        output += colored(header, .dim) + "\n"

        for (i, note) in notes.enumerated() {
            let num = padRight("\(i + 1)", width: 4)
            let title = padRight(String(note.title.prefix(18)), width: 20)
            let folder = padRight(note.folderName, width: 14)
            let snippet = highlightMatch(note.snippet, query: query)
            output += " \(num)\(colored(title, .white))\(colored(folder, .cyan))\(snippet)\n"
        }

        let summary = "\n\(notes.count) note\(notes.count == 1 ? "" : "s") matched \"\(query)\""
        output += colored(summary, .dim)
        return output
    }

    private static func highlightMatch(_ text: String, query: String) -> String {
        guard let range = text.lowercased().range(of: query.lowercased()) else {
            return colored("\"...\(String(text.prefix(30)))...\"", .dim)
        }
        let start = max(text.startIndex, text.index(range.lowerBound, offsetBy: -15, limitedBy: text.startIndex) ?? text.startIndex)
        let end = min(text.endIndex, text.index(range.upperBound, offsetBy: 15, limitedBy: text.endIndex) ?? text.endIndex)
        let excerpt = text[start..<end]
        return colored("\"...\(excerpt)...\"", .dim)
    }
}
```

- [ ] **Step 4: Implement JSONOutput**

Create `Sources/corenote/Output/JSONOutput.swift`:

```swift
import Foundation

enum JSONOutput {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func noteToJSON(_ note: Note, body: String? = nil) -> [String: Any] {
        var dict: [String: Any] = [
            "id": note.pk,
            "uuid": note.uuid,
            "title": note.title,
            "snippet": note.snippet,
            "folder": note.folderName,
            "account": note.accountName,
            "created": isoFormatter.string(from: note.createdAt),
            "modified": isoFormatter.string(from: note.modifiedAt),
            "trashed": note.isTrashed,
        ]
        if let body = body {
            dict["body"] = body
        }
        return dict
    }

    static func folderToJSON(_ folder: Folder) -> [String: Any] {
        [
            "id": folder.pk,
            "uuid": folder.uuid,
            "name": folder.name,
            "account": folder.accountName,
            "noteCount": folder.noteCount,
        ]
    }

    static func serialize(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func serializeNotes(_ notes: [Note]) throws -> String {
        try serialize(notes.map { noteToJSON($0) })
    }

    static func serializeFolders(_ folders: [Folder]) throws -> String {
        try serialize(folders.map { folderToJSON($0) })
    }

    static func serializeNote(_ note: Note, body: String? = nil) throws -> String {
        try serialize(noteToJSON(note, body: body))
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter FormatterTests 2>&1 | tail -5`
Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/corenote/Output/ Tests/corenoteTests/FormatterTests.swift
git commit -m "feat: add OutputFormatter with rich terminal output and JSONOutput for --json flag"
```

---

## Task 11: List Command

**Files:**
- Modify: `Sources/corenote/CoreNote.swift`
- Create: `Sources/corenote/Commands/ListCommand.swift`

- [ ] **Step 1: Create ListCommand**

Create `Sources/corenote/Commands/ListCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all notes"
    )

    @Option(name: .long, help: "Filter by folder name")
    var folder: String?

    @Option(name: .long, help: "Filter by account name")
    var account: String?

    @Option(name: .long, help: "Maximum number of results")
    var limit: Int = 50

    @Option(name: .long, help: "Sort by: modified, created, or title")
    var sort: String = "modified"

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let notes = try store.listNotes(folder: folder, account: account, limit: limit, sort: sort)

        if json {
            print(try JSONOutput.serializeNotes(notes))
        } else {
            print(OutputFormatter.formatNoteList(notes))
        }
    }
}
```

- [ ] **Step 2: Register ListCommand in root command**

Update `Sources/corenote/CoreNote.swift`:

```swift
import ArgumentParser

@main
struct CoreNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "corenote",
        abstract: "CLI frontend to Apple Notes",
        version: "0.1.0",
        subcommands: [ListCommand.self]
    )
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Verify help output**

Run: `.build/debug/corenote list --help`
Expected: Shows list command options (--folder, --account, --limit, --sort, --json).

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Commands/ListCommand.swift Sources/corenote/CoreNote.swift
git commit -m "feat: add list command with folder/account filtering, sorting, and JSON output"
```

---

## Task 12: Show Command

**Files:**
- Create: `Sources/corenote/Commands/ShowCommand.swift`
- Modify: `Sources/corenote/CoreNote.swift`

- [ ] **Step 1: Create ShowCommand**

Create `Sources/corenote/Commands/ShowCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a note's content"
    )

    @Argument(help: "Note title (fuzzy match) or ID")
    var query: String

    @Flag(name: .long, help: "Treat query as internal ID")
    var id: Bool = false

    @Flag(name: .long, help: "Show raw plain text (no Markdown rendering)")
    var raw: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let note = try resolveNote(query: query, useID: id, store: store)

        if note.isPasswordProtected {
            throw ValidationError("Note \"\(note.title)\" is encrypted \u{2014} cannot read")
        }

        guard let bodyData = try store.getNoteBody(notePK: note.pk) else {
            if json {
                print(try JSONOutput.serializeNote(note, body: "(empty note)"))
            } else {
                print(OutputFormatter.formatNoteDetail(note: note, body: "(empty note)"))
            }
            return
        }

        let decoded = try NoteBodyDecoder.decode(data: bodyData)

        if raw {
            if json {
                print(try JSONOutput.serializeNote(note, body: decoded.text))
            } else {
                print(decoded.text)
            }
        } else {
            let markdown = NoteToMarkdown.convert(decoded)
            if json {
                print(try JSONOutput.serializeNote(note, body: markdown))
            } else {
                print(OutputFormatter.formatNoteDetail(note: note, body: markdown))
            }
        }
    }
}

func resolveNote(query: String, useID: Bool, store: NoteStoreDB) throws -> Note {
    if useID {
        // Try as Z_PK first
        if let pk = Int64(query) {
            let notes = try store.listNotes(limit: Int.max)
            if let note = notes.first(where: { $0.pk == pk }) {
                return note
            }
        }
        // Try as UUID
        if let pk = try store.findNotePK(byUUID: query) {
            let notes = try store.listNotes(limit: Int.max)
            if let note = notes.first(where: { $0.pk == pk }) {
                return note
            }
        }
        throw NoteStoreError.noteNotFound(query: query)
    }

    let allNotes = try store.listNotes(limit: Int.max)
    let titles = allNotes.map { $0.title }
    let matches = FuzzyMatcher.match(query: query, candidates: titles)

    if matches.isEmpty {
        throw NoteStoreError.noteNotFound(query: query)
    }

    if matches.count == 1 {
        return allNotes.first { $0.title == matches[0] }!
    }

    // Multiple matches — prompt user
    if matches.count <= 5 {
        print("Multiple notes match \"\(query)\":")
        for (i, title) in matches.enumerated() {
            print("  \(i + 1). \(title)")
        }
        print("Enter number (1-\(matches.count)): ", terminator: "")
        guard let input = readLine(), let choice = Int(input),
              choice >= 1, choice <= matches.count else {
            throw ValidationError("Invalid selection")
        }
        return allNotes.first { $0.title == matches[choice - 1] }!
    }

    // Too many matches
    print("Too many matches for \"\(query)\". Showing first 10:")
    for title in matches.prefix(10) {
        print("  - \(title)")
    }
    throw ValidationError("Please narrow your search query")
}
```

- [ ] **Step 2: Register ShowCommand in root command**

Update `Sources/corenote/CoreNote.swift` subcommands array:

```swift
subcommands: [ListCommand.self, ShowCommand.self]
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/corenote/Commands/ShowCommand.swift Sources/corenote/CoreNote.swift
git commit -m "feat: add show command with fuzzy matching, raw mode, and JSON output"
```

---

## Task 13: Search Command

**Files:**
- Create: `Sources/corenote/Commands/SearchCommand.swift`
- Modify: `Sources/corenote/CoreNote.swift`

- [ ] **Step 1: Create SearchCommand**

Create `Sources/corenote/Commands/SearchCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Full-text search across notes"
    )

    @Argument(help: "Search text")
    var text: String

    @Option(name: .long, help: "Limit search to folder")
    var folder: String?

    @Option(name: .long, help: "Maximum number of results")
    var limit: Int = 50

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let notes = try store.searchNotes(text: text, folder: folder, limit: limit)

        if json {
            print(try JSONOutput.serializeNotes(notes))
        } else {
            print(OutputFormatter.formatSearchResults(notes, query: text))
        }
    }
}
```

- [ ] **Step 2: Register SearchCommand in root command**

Update subcommands:
```swift
subcommands: [ListCommand.self, ShowCommand.self, SearchCommand.self]
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/corenote/Commands/SearchCommand.swift Sources/corenote/CoreNote.swift
git commit -m "feat: add search command with folder filtering and JSON output"
```

---

## Task 14: Note Body Encoder

**Files:**
- Create: `Sources/corenote/Protobuf/NoteBodyEncoder.swift`
- Create: `Tests/corenoteTests/NoteBodyEncoderTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/corenoteTests/NoteBodyEncoderTests.swift`:

```swift
import XCTest
@testable import corenote

final class NoteBodyEncoderTests: XCTestCase {
    func testEncodeAndDecodeRoundTrip() throws {
        let body = DecodedNoteBody(
            text: "Hello World\n",
            runs: [DecodedRun(length: 12, paragraphStyle: nil, isBold: false,
                              isUnderlined: false, isStrikethrough: false,
                              link: nil, attachment: nil)]
        )

        let encoded = try NoteBodyEncoder.encode(body)

        // Verify it's gzipped
        XCTAssertTrue(GzipHelper.isGzipped(encoded))

        // Decode back and verify
        let decoded = try NoteBodyDecoder.decode(data: encoded)
        XCTAssertEqual(decoded.text, "Hello World\n")
        XCTAssertEqual(decoded.runs.count, 1)
    }

    func testEncodeWithFormatting() throws {
        let body = DecodedNoteBody(
            text: "Title\nBold text\n",
            runs: [
                DecodedRun(length: 6,
                    paragraphStyle: .init(styleType: .heading1, listStyle: nil, isChecklist: false,
                        isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 10, paragraphStyle: nil, isBold: true,
                    isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )

        let encoded = try NoteBodyEncoder.encode(body)
        let decoded = try NoteBodyDecoder.decode(data: encoded)

        XCTAssertEqual(decoded.text, "Title\nBold text\n")
        XCTAssertEqual(decoded.runs.count, 2)
        XCTAssertEqual(decoded.runs[0].paragraphStyle?.styleType, .heading1)
        XCTAssertTrue(decoded.runs[1].isBold)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter NoteBodyEncoderTests 2>&1 | tail -5`
Expected: Compilation error — `NoteBodyEncoder` not defined.

- [ ] **Step 3: Implement NoteBodyEncoder**

Create `Sources/corenote/Protobuf/NoteBodyEncoder.swift`:

```swift
import Foundation

enum NoteBodyEncoder {
    static func encode(_ body: DecodedNoteBody) throws -> Data {
        var note = CNNote()
        note.noteText = body.text

        note.attributeRun = body.runs.map { run -> CNAttributeRun in
            var protoRun = CNAttributeRun()
            protoRun.length = Int32(run.length)

            if let ps = run.paragraphStyle {
                var style = CNParagraphStyle()
                if let st = ps.styleType {
                    style.styleType = Int32(st.rawValue)
                }
                if let ls = ps.listStyle {
                    style.listStyle = Int32(ls)
                }
                if ps.isChecklist {
                    var checklist = CNChecklist()
                    checklist.done = ps.isChecklistDone ? 1 : 0
                    style.checklist = checklist
                }
                if ps.isBlockquote {
                    style.blockquote = 1
                }
                if ps.indentAmount > 0 {
                    style.indentAmount = Int32(ps.indentAmount)
                }
                protoRun.paragraphStyle = style
            }

            if run.isBold {
                protoRun.fontWeight = 1
            }
            if run.isUnderlined {
                protoRun.underlined = 1
            }
            if run.isStrikethrough {
                protoRun.strikethrough = 1
            }
            if let link = run.link {
                protoRun.link = link
            }
            if let att = run.attachment {
                var info = CNAttachmentInfo()
                info.attachmentIdentifier = att.identifier
                info.typeUti = att.typeUTI
                protoRun.attachmentInfo = info
            }

            return protoRun
        }

        var doc = CNDocument()
        doc.note = note

        var proto = CNNoteStoreProto()
        proto.document = doc

        let rawData = try proto.serializedData()
        return try GzipHelper.compress(rawData)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter NoteBodyEncoderTests 2>&1 | tail -5`
Expected: All 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Protobuf/NoteBodyEncoder.swift Tests/corenoteTests/NoteBodyEncoderTests.swift
git commit -m "feat: add NoteBodyEncoder with protobuf serialization and gzip compression"
```

---

## Task 15: Markdown to Note Converter

**Files:**
- Create: `Sources/corenote/Converter/MarkdownToNote.swift`
- Create: `Tests/corenoteTests/MarkdownToNoteTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/corenoteTests/MarkdownToNoteTests.swift`:

```swift
import XCTest
@testable import corenote

final class MarkdownToNoteTests: XCTestCase {
    func testPlainText() {
        let result = MarkdownToNote.convert("Hello World")
        XCTAssertEqual(result.text, "Hello World\n")
        XCTAssertEqual(result.runs.count, 1)
        XCTAssertEqual(result.runs[0].length, 12)
    }

    func testHeading() {
        let result = MarkdownToNote.convert("# My Title")
        XCTAssertEqual(result.text, "My Title\n")
        XCTAssertEqual(result.runs[0].paragraphStyle?.styleType, .heading1)
    }

    func testHeading2() {
        let result = MarkdownToNote.convert("## Subtitle")
        XCTAssertEqual(result.text, "Subtitle\n")
        XCTAssertEqual(result.runs[0].paragraphStyle?.styleType, .heading2)
    }

    func testBoldText() {
        let result = MarkdownToNote.convert("Hello **bold** world")
        XCTAssertEqual(result.text, "Hello bold world\n")
        // Should have 3 runs: "Hello ", "bold", " world\n"
        XCTAssertTrue(result.runs.contains { $0.isBold })
    }

    func testStrikethrough() {
        let result = MarkdownToNote.convert("~~removed~~")
        XCTAssertEqual(result.text, "removed\n")
        XCTAssertTrue(result.runs[0].isStrikethrough)
    }

    func testBulletList() {
        let result = MarkdownToNote.convert("- Item 1\n- Item 2")
        XCTAssertEqual(result.text, "Item 1\nItem 2\n")
        XCTAssertEqual(result.runs[0].paragraphStyle?.listStyle, 100)
        XCTAssertEqual(result.runs[1].paragraphStyle?.listStyle, 100)
    }

    func testNumberedList() {
        let result = MarkdownToNote.convert("1. First\n2. Second")
        XCTAssertEqual(result.text, "First\nSecond\n")
        XCTAssertEqual(result.runs[0].paragraphStyle?.listStyle, 200)
    }

    func testChecklist() {
        let result = MarkdownToNote.convert("- [x] Done\n- [ ] Not done")
        XCTAssertEqual(result.text, "Done\nNot done\n")
        XCTAssertTrue(result.runs[0].paragraphStyle?.isChecklist == true)
        XCTAssertTrue(result.runs[0].paragraphStyle?.isChecklistDone == true)
        XCTAssertTrue(result.runs[1].paragraphStyle?.isChecklist == true)
        XCTAssertFalse(result.runs[1].paragraphStyle?.isChecklistDone == true)
    }

    func testBlockquote() {
        let result = MarkdownToNote.convert("> Quoted text")
        XCTAssertEqual(result.text, "Quoted text\n")
        XCTAssertTrue(result.runs[0].paragraphStyle?.isBlockquote == true)
    }

    func testLink() {
        let result = MarkdownToNote.convert("[click](https://example.com)")
        XCTAssertEqual(result.text, "click\n")
        XCTAssertEqual(result.runs[0].link, "https://example.com")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MarkdownToNoteTests 2>&1 | tail -5`
Expected: Compilation error — `MarkdownToNote` not defined.

- [ ] **Step 3: Implement MarkdownToNote**

Create `Sources/corenote/Converter/MarkdownToNote.swift`:

```swift
import Foundation

enum MarkdownToNote {
    static func convert(_ markdown: String) -> DecodedNoteBody {
        var plainText = ""
        var runs: [DecodedRun] = []

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (lineIdx, line) in lines.enumerated() {
            let parsed = parseLine(line)
            let lineText = parsed.text + "\n"
            let startIndex = plainText.count

            plainText += lineText

            for segment in parsed.segments {
                let run = DecodedRun(
                    length: segment.text.count,
                    paragraphStyle: parsed.paragraphStyle,
                    isBold: segment.isBold,
                    isUnderlined: segment.isUnderlined,
                    isStrikethrough: segment.isStrikethrough,
                    link: segment.link,
                    attachment: nil
                )
                runs.append(run)
            }

            // If no segments, create a run for the whole line including newline
            if parsed.segments.isEmpty {
                runs.append(DecodedRun(
                    length: lineText.count,
                    paragraphStyle: parsed.paragraphStyle,
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil
                ))
            } else {
                // Account for trailing newline in last segment
                if let lastIdx = runs.indices.last {
                    let last = runs[lastIdx]
                    runs[lastIdx] = DecodedRun(
                        length: last.length + 1, // +1 for \n
                        paragraphStyle: last.paragraphStyle,
                        isBold: last.isBold,
                        isUnderlined: last.isUnderlined,
                        isStrikethrough: last.isStrikethrough,
                        link: last.link,
                        attachment: last.attachment
                    )
                }
            }
        }

        // Merge adjacent runs with identical formatting
        runs = mergeRuns(runs)

        return DecodedNoteBody(text: plainText, runs: runs)
    }

    private struct ParsedLine {
        let text: String
        let paragraphStyle: DecodedRun.DecodedParagraphStyle?
        let segments: [InlineSegment]
    }

    private struct InlineSegment {
        let text: String
        let isBold: Bool
        let isUnderlined: Bool
        let isStrikethrough: Bool
        let link: String?
    }

    private static func parseLine(_ line: String) -> ParsedLine {
        var text = line
        var style: DecodedRun.DecodedParagraphStyle?

        // Headings
        if let match = text.range(of: #"^(#{1,3})\s+"#, options: .regularExpression) {
            let hashes = text[match].filter { $0 == "#" }.count
            let styleType: DecodedRun.DecodedParagraphStyle.StyleType
            switch hashes {
            case 1: styleType = .heading1
            case 2: styleType = .heading2
            default: styleType = .heading3
            }
            text = String(text[match.upperBound...])
            style = .init(styleType: styleType, listStyle: nil, isChecklist: false,
                          isChecklistDone: false, isBlockquote: false, indentAmount: 0)
        }
        // Checklist
        else if let match = text.range(of: #"^- \[([ xX])\] "#, options: .regularExpression) {
            let checkChar = text[text.index(text.startIndex, offsetBy: 3)]
            let isDone = checkChar == "x" || checkChar == "X"
            text = String(text[match.upperBound...])
            style = .init(styleType: nil, listStyle: nil, isChecklist: true,
                          isChecklistDone: isDone, isBlockquote: false, indentAmount: 0)
        }
        // Bullet list
        else if let match = text.range(of: #"^(\s*)- "#, options: .regularExpression) {
            let indent = text[match].filter { $0 == " " }.count / 2
            text = String(text[match.upperBound...])
            style = .init(styleType: nil, listStyle: 100, isChecklist: false,
                          isChecklistDone: false, isBlockquote: false, indentAmount: indent)
        }
        // Numbered list
        else if let match = text.range(of: #"^(\s*)\d+\. "#, options: .regularExpression) {
            let indent = text[match].filter { $0 == " " }.count / 2
            text = String(text[match.upperBound...])
            style = .init(styleType: nil, listStyle: 200, isChecklist: false,
                          isChecklistDone: false, isBlockquote: false, indentAmount: indent)
        }
        // Blockquote
        else if text.hasPrefix("> ") {
            text = String(text.dropFirst(2))
            style = .init(styleType: nil, listStyle: nil, isChecklist: false,
                          isChecklistDone: false, isBlockquote: true, indentAmount: 0)
        }

        let segments = parseInlineFormatting(text)
        let plainText = segments.map { $0.text }.joined()

        return ParsedLine(text: plainText, paragraphStyle: style, segments: segments)
    }

    private static func parseInlineFormatting(_ text: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var remaining = text

        while !remaining.isEmpty {
            // Bold: **text**
            if let range = remaining.range(of: #"\*\*(.+?)\*\*"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    segments.append(InlineSegment(text: before, isBold: false, isUnderlined: false, isStrikethrough: false, link: nil))
                }
                let inner = String(remaining[range]).dropFirst(2).dropLast(2)
                segments.append(InlineSegment(text: String(inner), isBold: true, isUnderlined: false, isStrikethrough: false, link: nil))
                remaining = String(remaining[range.upperBound...])
                continue
            }

            // Strikethrough: ~~text~~
            if let range = remaining.range(of: #"~~(.+?)~~"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    segments.append(InlineSegment(text: before, isBold: false, isUnderlined: false, isStrikethrough: false, link: nil))
                }
                let inner = String(remaining[range]).dropFirst(2).dropLast(2)
                segments.append(InlineSegment(text: String(inner), isBold: false, isUnderlined: false, isStrikethrough: true, link: nil))
                remaining = String(remaining[range.upperBound...])
                continue
            }

            // Link: [text](url)
            if let range = remaining.range(of: #"\[(.+?)\]\((.+?)\)"#, options: .regularExpression) {
                let before = String(remaining[remaining.startIndex..<range.lowerBound])
                if !before.isEmpty {
                    segments.append(InlineSegment(text: before, isBold: false, isUnderlined: false, isStrikethrough: false, link: nil))
                }
                let matched = String(remaining[range])
                // Extract text and URL
                if let textRange = matched.range(of: #"\[(.+?)\]"#, options: .regularExpression),
                   let urlRange = matched.range(of: #"\((.+?)\)"#, options: .regularExpression) {
                    let linkText = String(matched[textRange]).dropFirst().dropLast()
                    let linkURL = String(matched[urlRange]).dropFirst().dropLast()
                    segments.append(InlineSegment(text: String(linkText), isBold: false, isUnderlined: false, isStrikethrough: false, link: String(linkURL)))
                }
                remaining = String(remaining[range.upperBound...])
                continue
            }

            // No more patterns — rest is plain text
            segments.append(InlineSegment(text: remaining, isBold: false, isUnderlined: false, isStrikethrough: false, link: nil))
            break
        }

        return segments
    }

    private static func mergeRuns(_ runs: [DecodedRun]) -> [DecodedRun] {
        guard !runs.isEmpty else { return runs }
        var merged: [DecodedRun] = [runs[0]]

        for run in runs.dropFirst() {
            let last = merged[merged.count - 1]
            if canMerge(last, run) {
                merged[merged.count - 1] = DecodedRun(
                    length: last.length + run.length,
                    paragraphStyle: last.paragraphStyle,
                    isBold: last.isBold,
                    isUnderlined: last.isUnderlined,
                    isStrikethrough: last.isStrikethrough,
                    link: last.link,
                    attachment: last.attachment
                )
            } else {
                merged.append(run)
            }
        }

        return merged
    }

    private static func canMerge(_ a: DecodedRun, _ b: DecodedRun) -> Bool {
        a.isBold == b.isBold &&
        a.isUnderlined == b.isUnderlined &&
        a.isStrikethrough == b.isStrikethrough &&
        a.link == b.link &&
        a.attachment == nil && b.attachment == nil &&
        stylesEqual(a.paragraphStyle, b.paragraphStyle)
    }

    private static func stylesEqual(_ a: DecodedRun.DecodedParagraphStyle?, _ b: DecodedRun.DecodedParagraphStyle?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a?, b?):
            return a.styleType == b.styleType &&
                   a.listStyle == b.listStyle &&
                   a.isChecklist == b.isChecklist &&
                   a.isChecklistDone == b.isChecklistDone &&
                   a.isBlockquote == b.isBlockquote &&
                   a.indentAmount == b.indentAmount
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MarkdownToNoteTests 2>&1 | tail -5`
Expected: All 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Converter/MarkdownToNote.swift Tests/corenoteTests/MarkdownToNoteTests.swift
git commit -m "feat: add MarkdownToNote converter with headings, bold, strikethrough, lists, links"
```

---

## Task 16: NoteStoreDB Write Queries

**Files:**
- Modify: `Sources/corenote/Database/NoteStoreDB.swift`

- [ ] **Step 1: Add write methods to NoteStoreDB**

Add to `Sources/corenote/Database/NoteStoreDB.swift`:

```swift
// MARK: - Write operations

extension NoteStoreDB {
    func createNote(title: String, bodyData: Data, folderPK: Int64?) throws -> Int64 {
        let now = Note.macFromDate(Date())
        let uuid = UUID().uuidString

        // Insert into ZICCLOUDSYNCINGOBJECT
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_ENT, ZTITLE1, ZIDENTIFIER,
                ZCREATIONDATE1, ZMODIFICATIONDATE1, ZFOLDER, ZMARKEDFORDELETION, ZISINTRASHEDBYUSER)
            VALUES (?, ?, ?, ?, ?, ?, 0, 0)
        """, params: [
            .int(schema.noteEnt), .text(title), .text(uuid),
            .double(now), .double(now),
            folderPK.map { .int($0) } ?? .null
        ])

        let noteRows = try db.query("SELECT last_insert_rowid() as pk")
        guard let notePK = noteRows.first?["pk"] as? Int64 else {
            throw NoteStoreError.noteNotFound(query: title)
        }

        // Insert note body into ZICNOTEDATA
        try db.execute("""
            INSERT INTO ZICNOTEDATA (ZNOTE, ZDATA) VALUES (?, ?)
        """, params: [.int(notePK), .blob(bodyData)])

        let dataRows = try db.query("SELECT last_insert_rowid() as pk")
        guard let dataPK = dataRows.first?["pk"] as? Int64 else {
            throw NoteStoreError.noteNotFound(query: title)
        }

        // Link note to its data
        try db.execute("""
            UPDATE ZICCLOUDSYNCINGOBJECT SET ZNOTEDATA = ? WHERE Z_PK = ?
        """, params: [.int(dataPK), .int(notePK)])

        return notePK
    }

    func updateNoteBody(notePK: Int64, bodyData: Data, title: String? = nil) throws {
        let now = Note.macFromDate(Date())

        // Update body data
        try db.execute("""
            UPDATE ZICNOTEDATA SET ZDATA = ?
            WHERE Z_PK = (SELECT ZNOTEDATA FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?)
        """, params: [.blob(bodyData), .int(notePK)])

        // Update modification date and optionally title
        if let title = title {
            try db.execute("""
                UPDATE ZICCLOUDSYNCINGOBJECT SET ZMODIFICATIONDATE1 = ?, ZTITLE1 = ? WHERE Z_PK = ?
            """, params: [.double(now), .text(title), .int(notePK)])
        } else {
            try db.execute("""
                UPDATE ZICCLOUDSYNCINGOBJECT SET ZMODIFICATIONDATE1 = ? WHERE Z_PK = ?
            """, params: [.double(now), .int(notePK)])
        }
    }

    func trashNote(notePK: Int64) throws {
        let now = Note.macFromDate(Date())
        try db.execute("""
            UPDATE ZICCLOUDSYNCINGOBJECT SET ZISINTRASHEDBYUSER = 1, ZMODIFICATIONDATE1 = ? WHERE Z_PK = ?
        """, params: [.double(now), .int(notePK)])
    }

    func permanentlyDeleteNote(notePK: Int64) throws {
        try db.execute("""
            DELETE FROM ZICNOTEDATA WHERE Z_PK = (SELECT ZNOTEDATA FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?)
        """, params: [.int(notePK)])
        try db.execute("DELETE FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?", params: [.int(notePK)])
    }

    func moveNote(notePK: Int64, toFolderPK: Int64) throws {
        let now = Note.macFromDate(Date())
        try db.execute("""
            UPDATE ZICCLOUDSYNCINGOBJECT SET ZFOLDER = ?, ZMODIFICATIONDATE1 = ? WHERE Z_PK = ?
        """, params: [.int(toFolderPK), .double(now), .int(notePK)])
    }

    func createFolder(name: String, parentPK: Int64?, accountPK: Int64?) throws -> Int64 {
        let uuid = UUID().uuidString
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_ENT, ZTITLE2, ZIDENTIFIER, ZPARENT, ZACCOUNT3)
            VALUES (?, ?, ?, ?, ?)
        """, params: [
            .int(schema.folderEnt), .text(name), .text(uuid),
            parentPK.map { .int($0) } ?? .null,
            accountPK.map { .int($0) } ?? .null
        ])

        let rows = try db.query("SELECT last_insert_rowid() as pk")
        return rows.first?["pk"] as? Int64 ?? 0
    }

    func renameFolder(folderPK: Int64, newName: String) throws {
        try db.execute("""
            UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE2 = ? WHERE Z_PK = ? AND Z_ENT = ?
        """, params: [.text(newName), .int(folderPK), .int(schema.folderEnt)])
    }

    func deleteFolder(folderPK: Int64) throws {
        try db.execute("""
            DELETE FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ? AND Z_ENT = ?
        """, params: [.int(folderPK), .int(schema.folderEnt)])
    }

    func getDefaultAccountPK() throws -> Int64? {
        let rows = try db.query(
            "SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT = ? LIMIT 1",
            params: [.int(schema.accountEnt)]
        )
        return rows.first?["Z_PK"] as? Int64
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/corenote/Database/NoteStoreDB.swift
git commit -m "feat: add write operations to NoteStoreDB (create, update, trash, delete, move, folders)"
```

---

## Task 17: Create Command

**Files:**
- Create: `Sources/corenote/Commands/CreateCommand.swift`
- Create: `Sources/corenote/Utilities/EditorLauncher.swift`
- Modify: `Sources/corenote/CoreNote.swift`

- [ ] **Step 1: Implement EditorLauncher**

Create `Sources/corenote/Utilities/EditorLauncher.swift`:

```swift
import Foundation

enum EditorError: Error, LocalizedError {
    case noEditorFound
    case editorFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .noEditorFound:
            return "No editor found. Set $EDITOR environment variable."
        case .editorFailed(let code):
            return "Editor exited with code \(code)"
        }
    }
}

enum EditorLauncher {
    static func edit(content: String, filename: String = "corenote-temp.md") throws -> String {
        let tempPath = NSTemporaryDirectory() + filename
        try content.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let editor = findEditor()
        guard let editor = editor else { throw EditorError.noEditorFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, tempPath]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw EditorError.editorFailed(process.terminationStatus)
        }

        return try String(contentsOfFile: tempPath, encoding: .utf8)
    }

    private static func findEditor() -> String? {
        if let editor = ProcessInfo.processInfo.environment["EDITOR"], !editor.isEmpty {
            return editor
        }
        for candidate in ["vim", "nano", "vi"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [candidate]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 { return candidate }
        }
        return nil
    }
}
```

- [ ] **Step 2: Create CreateCommand**

Create `Sources/corenote/Commands/CreateCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct CreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new note"
    )

    @Option(name: .long, help: "Note title")
    var title: String?

    @Option(name: .long, help: "Note body (Markdown)")
    var body: String?

    @Option(name: .long, help: "Target folder (default: Notes)")
    var folder: String?

    @Flag(name: .long, help: "Open in $EDITOR")
    var editor: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)

        warnIfNotesRunning(store)

        var noteTitle: String
        var noteBody: String

        if editor {
            let template = "# \(title ?? "Untitled")\n\n"
            let edited = try EditorLauncher.edit(content: template, filename: "corenote-new.md")
            let lines = edited.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            noteTitle = String(lines.first ?? "Untitled")
            if noteTitle.hasPrefix("# ") { noteTitle = String(noteTitle.dropFirst(2)) }
            noteBody = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        } else {
            guard let t = title else {
                throw ValidationError("--title is required (or use --editor)")
            }
            noteTitle = t
            noteBody = body ?? ""
        }

        // Convert to protobuf
        let markdown = noteBody.isEmpty ? noteTitle + "\n" : "# \(noteTitle)\n\(noteBody)\n"
        let decoded = MarkdownToNote.convert(markdown)
        let encoded = try NoteBodyEncoder.encode(decoded)

        // Find folder
        let folderPK: Int64?
        if let folderName = folder {
            folderPK = try store.findFolderPK(byName: folderName)
            if folderPK == nil {
                throw NoteStoreError.folderNotFound(name: folderName)
            }
        } else {
            folderPK = try store.findFolderPK(byName: "Notes")
        }

        let pk = try store.createNote(title: noteTitle, bodyData: encoded, folderPK: folderPK)
        print(OutputFormatter.colored("Created note \"\(noteTitle)\" (id: \(pk))", .green))
    }
}

func warnIfNotesRunning(_ store: NoteStoreDB) {
    if store.isNotesAppRunning() {
        print(OutputFormatter.colored(
            "Warning: Notes.app is running. Changes may conflict with sync.",
            .yellow
        ))
    }
}

func confirmAction(_ prompt: String) -> Bool {
    print("\(prompt) [y/N] ", terminator: "")
    guard let input = readLine()?.lowercased() else { return false }
    return input == "y" || input == "yes"
}
```

- [ ] **Step 3: Register CreateCommand in root command**

Update subcommands:
```swift
subcommands: [ListCommand.self, ShowCommand.self, SearchCommand.self, CreateCommand.self]
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Utilities/EditorLauncher.swift Sources/corenote/Commands/CreateCommand.swift Sources/corenote/CoreNote.swift
git commit -m "feat: add create command with --editor and --body modes"
```

---

## Task 18: Edit Command

**Files:**
- Create: `Sources/corenote/Commands/EditCommand.swift`
- Modify: `Sources/corenote/CoreNote.swift`

- [ ] **Step 1: Create EditCommand**

Create `Sources/corenote/Commands/EditCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct EditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit",
        abstract: "Edit an existing note"
    )

    @Argument(help: "Note title (fuzzy match) or ID")
    var query: String

    @Flag(name: .long, help: "Treat query as internal ID")
    var id: Bool = false

    @Option(name: .long, help: "Replace body with this text (Markdown)")
    var body: String?

    @Option(name: .long, help: "Update title")
    var title: String?

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let note = try resolveNote(query: query, useID: id, store: store)

        if note.isPasswordProtected {
            throw ValidationError("Note \"\(note.title)\" is encrypted \u{2014} cannot edit")
        }

        warnIfNotesRunning(store)

        if let newBody = body {
            // Inline edit mode
            let markdown = "# \(title ?? note.title)\n\(newBody)\n"
            let decoded = MarkdownToNote.convert(markdown)
            let encoded = try NoteBodyEncoder.encode(decoded)
            try store.updateNoteBody(notePK: note.pk, bodyData: encoded, title: title)
            print(OutputFormatter.colored("Updated \"\(title ?? note.title)\"", .green))
        } else {
            // Editor mode
            guard let bodyData = try store.getNoteBody(notePK: note.pk) else {
                throw ValidationError("Cannot read note body for \"\(note.title)\"")
            }

            let decoded = try NoteBodyDecoder.decode(data: bodyData)
            let originalMarkdown = NoteToMarkdown.convert(decoded)

            let edited = try EditorLauncher.edit(
                content: originalMarkdown,
                filename: "corenote-\(note.pk).md"
            )

            if edited.trimmingCharacters(in: .whitespacesAndNewlines) ==
               originalMarkdown.trimmingCharacters(in: .whitespacesAndNewlines) {
                print("No changes made.")
                return
            }

            let newDecoded = MarkdownToNote.convert(edited)
            let encoded = try NoteBodyEncoder.encode(newDecoded)

            // Extract title from first line if it's a heading
            var newTitle = title
            if newTitle == nil {
                let firstLine = edited.split(separator: "\n").first.map(String.init) ?? note.title
                if firstLine.hasPrefix("# ") {
                    newTitle = String(firstLine.dropFirst(2))
                }
            }

            try store.updateNoteBody(notePK: note.pk, bodyData: encoded, title: newTitle)
            print(OutputFormatter.colored("Updated \"\(newTitle ?? note.title)\"", .green))
        }
    }
}
```

- [ ] **Step 2: Register EditCommand**

Update subcommands:
```swift
subcommands: [ListCommand.self, ShowCommand.self, SearchCommand.self, CreateCommand.self, EditCommand.self]
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/corenote/Commands/EditCommand.swift Sources/corenote/CoreNote.swift
git commit -m "feat: add edit command with $EDITOR and --body modes"
```

---

## Task 19: Delete and Move Commands

**Files:**
- Create: `Sources/corenote/Commands/DeleteCommand.swift`
- Create: `Sources/corenote/Commands/MoveCommand.swift`
- Modify: `Sources/corenote/CoreNote.swift`

- [ ] **Step 1: Create DeleteCommand**

Create `Sources/corenote/Commands/DeleteCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Move a note to Recently Deleted"
    )

    @Argument(help: "Note title (fuzzy match) or ID")
    var query: String

    @Flag(name: .long, help: "Treat query as internal ID")
    var id: Bool = false

    @Flag(name: .long, help: "Permanently delete (cannot be undone)")
    var permanent: Bool = false

    @Flag(name: .long, help: "Skip confirmation prompt")
    var force: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let note = try resolveNote(query: query, useID: id, store: store)

        warnIfNotesRunning(store)

        if permanent {
            if !force {
                guard confirmAction("PERMANENTLY delete \"\(note.title)\"? This cannot be undone.") else {
                    print("Cancelled.")
                    return
                }
            }
            try store.permanentlyDeleteNote(notePK: note.pk)
            print(OutputFormatter.colored("Permanently deleted \"\(note.title)\"", .red))
        } else {
            if !force {
                guard confirmAction("Delete \"\(note.title)\"? This moves it to Recently Deleted.") else {
                    print("Cancelled.")
                    return
                }
            }
            try store.trashNote(notePK: note.pk)
            print(OutputFormatter.colored("Moved \"\(note.title)\" to Recently Deleted", .yellow))
        }
    }
}
```

- [ ] **Step 2: Create MoveCommand**

Create `Sources/corenote/Commands/MoveCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct MoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move a note to another folder"
    )

    @Argument(help: "Note title (fuzzy match) or ID")
    var query: String

    @Option(name: .long, help: "Target folder name")
    var to: String

    @Flag(name: .long, help: "Treat query as internal ID")
    var id: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let note = try resolveNote(query: query, useID: id, store: store)

        guard let folderPK = try store.findFolderPK(byName: to) else {
            throw NoteStoreError.folderNotFound(name: to)
        }

        warnIfNotesRunning(store)
        try store.moveNote(notePK: note.pk, toFolderPK: folderPK)
        print(OutputFormatter.colored("Moved \"\(note.title)\" to \(to)", .green))
    }
}
```

- [ ] **Step 3: Register both commands**

Update subcommands:
```swift
subcommands: [
    ListCommand.self, ShowCommand.self, SearchCommand.self,
    CreateCommand.self, EditCommand.self, DeleteCommand.self,
    MoveCommand.self,
]
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/corenote/Commands/DeleteCommand.swift Sources/corenote/Commands/MoveCommand.swift Sources/corenote/CoreNote.swift
git commit -m "feat: add delete command (trash/permanent) and move command"
```

---

## Task 20: Folder Commands

**Files:**
- Create: `Sources/corenote/Commands/Folder/FolderGroup.swift`
- Create: `Sources/corenote/Commands/Folder/FolderListCommand.swift`
- Create: `Sources/corenote/Commands/Folder/FolderCreateCommand.swift`
- Create: `Sources/corenote/Commands/Folder/FolderRenameCommand.swift`
- Create: `Sources/corenote/Commands/Folder/FolderDeleteCommand.swift`
- Modify: `Sources/corenote/CoreNote.swift`

- [ ] **Step 1: Create FolderGroup**

Create `Sources/corenote/Commands/Folder/FolderGroup.swift`:

```swift
import ArgumentParser

struct FolderGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folder",
        abstract: "Manage folders",
        subcommands: [
            FolderListCommand.self,
            FolderCreateCommand.self,
            FolderRenameCommand.self,
            FolderDeleteCommand.self,
        ],
        defaultSubcommand: FolderListCommand.self
    )
}
```

- [ ] **Step 2: Create FolderListCommand**

Create `Sources/corenote/Commands/Folder/FolderListCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct FolderListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all folders"
    )

    @Option(name: .long, help: "Filter by account name")
    var account: String?

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let folders = try store.listFolders(account: account)

        if json {
            print(try JSONOutput.serializeFolders(folders))
        } else {
            print(OutputFormatter.formatFolderList(folders))
        }
    }
}
```

- [ ] **Step 3: Create FolderCreateCommand**

Create `Sources/corenote/Commands/Folder/FolderCreateCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct FolderCreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new folder"
    )

    @Argument(help: "Folder name")
    var name: String

    @Option(name: .long, help: "Parent folder name (for nesting)")
    var parent: String?

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)

        warnIfNotesRunning(store)

        var parentPK: Int64?
        if let parentName = parent {
            parentPK = try store.findFolderPK(byName: parentName)
            if parentPK == nil {
                throw NoteStoreError.folderNotFound(name: parentName)
            }
        }

        let accountPK = try store.getDefaultAccountPK()
        let pk = try store.createFolder(name: name, parentPK: parentPK, accountPK: accountPK)
        print(OutputFormatter.colored("Created folder \"\(name)\" (id: \(pk))", .green))
    }
}
```

- [ ] **Step 4: Create FolderRenameCommand**

Create `Sources/corenote/Commands/Folder/FolderRenameCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct FolderRenameCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a folder"
    )

    @Argument(help: "Current folder name")
    var query: String

    @Option(name: .long, help: "New folder name")
    var name: String

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)

        guard let folderPK = try store.findFolderPK(byName: query) else {
            throw NoteStoreError.folderNotFound(name: query)
        }

        warnIfNotesRunning(store)
        try store.renameFolder(folderPK: folderPK, newName: name)
        print(OutputFormatter.colored("Renamed \"\(query)\" to \"\(name)\"", .green))
    }
}
```

- [ ] **Step 5: Create FolderDeleteCommand**

Create `Sources/corenote/Commands/Folder/FolderDeleteCommand.swift`:

```swift
import ArgumentParser
import Foundation

struct FolderDeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a folder"
    )

    @Argument(help: "Folder name")
    var query: String

    @Flag(name: .long, help: "Skip confirmation prompt")
    var force: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)

        guard let folderPK = try store.findFolderPK(byName: query) else {
            throw NoteStoreError.folderNotFound(name: query)
        }

        if !force {
            guard confirmAction("Delete folder \"\(query)\" and all its notes?") else {
                print("Cancelled.")
                return
            }
        }

        warnIfNotesRunning(store)
        try store.deleteFolder(folderPK: folderPK)
        print(OutputFormatter.colored("Deleted folder \"\(query)\"", .red))
    }
}
```

- [ ] **Step 6: Register FolderGroup in root command**

Final `Sources/corenote/CoreNote.swift`:

```swift
import ArgumentParser

@main
struct CoreNote: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "corenote",
        abstract: "CLI frontend to Apple Notes",
        version: "0.1.0",
        subcommands: [
            ListCommand.self,
            ShowCommand.self,
            SearchCommand.self,
            CreateCommand.self,
            EditCommand.self,
            DeleteCommand.self,
            MoveCommand.self,
            FolderGroup.self,
        ]
    )
}
```

- [ ] **Step 7: Verify it builds**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 8: Verify folder help output**

Run: `.build/debug/corenote folder --help`
Expected: Shows folder subcommands (list, create, rename, delete).

- [ ] **Step 9: Commit**

```bash
git add Sources/corenote/Commands/Folder/ Sources/corenote/CoreNote.swift
git commit -m "feat: add folder commands (list, create, rename, delete)"
```

---

## Task 21: Run All Tests and Final Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 2: Run full build in release mode**

Run: `swift build -c release 2>&1 | tail -5`
Expected: Release build succeeds.

- [ ] **Step 3: Verify all commands are registered**

Run: `.build/debug/corenote --help`
Expected output includes: list, show, search, create, edit, delete, move, folder.

- [ ] **Step 4: Verify version flag**

Run: `.build/debug/corenote --version`
Expected: `0.1.0`

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address issues found during final verification"
```
