import XCTest
@testable import corenote

final class SchemaCompatTests: XCTestCase {

    // MARK: - Helpers

    private func createBaseDB(
        mainColumns: [String] = [],
        noteDataColumns: [String] = ["Z_PK INTEGER PRIMARY KEY", "ZDATA BLOB", "ZNOTE INTEGER"]
    ) throws -> SQLiteConnection {
        let db = try SQLiteConnection(path: ":memory:")

        // Z_PRIMARYKEY
        try db.execute("""
            CREATE TABLE Z_PRIMARYKEY (
                Z_ENT INTEGER PRIMARY KEY, Z_NAME TEXT, Z_SUPER INTEGER, Z_MAX INTEGER
            )
        """)
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (6, 'ICAccount')")
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (9, 'ICFolder')")
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (14, 'ICNote')")

        // ZICCLOUDSYNCINGOBJECT with configurable columns
        let defaultCols = [
            "Z_PK INTEGER PRIMARY KEY", "Z_ENT INTEGER",
            "ZTITLE1 TEXT", "ZTITLE2 TEXT", "ZIDENTIFIER TEXT",
            "ZCREATIONDATE1 REAL", "ZMODIFICATIONDATE1 REAL",
            "ZFOLDER INTEGER", "ZNOTEDATA INTEGER"
        ]
        let allCols = defaultCols + mainColumns
        try db.execute("CREATE TABLE ZICCLOUDSYNCINGOBJECT (\(allCols.joined(separator: ", ")))")

        // ZICNOTEDATA
        try db.execute("CREATE TABLE ZICNOTEDATA (\(noteDataColumns.joined(separator: ", ")))")

        return db
    }

    private func fullSchemaDB() throws -> SQLiteConnection {
        try createBaseDB(mainColumns: [
            "ZSNIPPET TEXT", "ZISPASSWORDPROTECTED INTEGER",
            "ZMARKEDFORDELETION INTEGER", "ZISINTRASHEDBYUSER INTEGER",
            "ZFOLDERTYPE INTEGER", "ZACCOUNT2 INTEGER", "ZACCOUNT3 INTEGER",
            "ZPARENT INTEGER", "ZNAME TEXT"
        ])
    }

    private func minimalSchemaDB() throws -> SQLiteConnection {
        // Only required columns, no optional ones
        try createBaseDB(mainColumns: [])
    }

    // MARK: - SchemaMapper: Column Detection

    func testDetectsMainTableColumns() throws {
        let db = try fullSchemaDB()
        defer { db.close() }

        let mapper = try SchemaMapper(db: db)
        XCTAssertTrue(mapper.has("Z_PK"))
        XCTAssertTrue(mapper.has("ZTITLE1"))
        XCTAssertTrue(mapper.has("ZSNIPPET"))
        XCTAssertTrue(mapper.has("ZISPASSWORDPROTECTED"))
        XCTAssertTrue(mapper.has("ZISINTRASHEDBYUSER"))
        XCTAssertTrue(mapper.has("ZFOLDERTYPE"))
        XCTAssertTrue(mapper.has("ZACCOUNT2"))
        XCTAssertTrue(mapper.has("ZACCOUNT3"))
        XCTAssertTrue(mapper.has("ZPARENT"))
    }

    func testHasReturnsFalseForMissingColumn() throws {
        let db = try minimalSchemaDB()
        defer { db.close() }

        let mapper = try SchemaMapper(db: db)
        XCTAssertFalse(mapper.has("ZSNIPPET"))
        XCTAssertFalse(mapper.has("ZISPASSWORDPROTECTED"))
        XCTAssertFalse(mapper.has("ZISINTRASHEDBYUSER"))
        XCTAssertFalse(mapper.has("ZFOLDERTYPE"))
        XCTAssertFalse(mapper.has("ZACCOUNT2"))
        XCTAssertFalse(mapper.has("ZACCOUNT3"))
        XCTAssertFalse(mapper.has("ZPARENT"))
    }

    func testDetectsNoteDataColumns() throws {
        let db = try fullSchemaDB()
        defer { db.close() }

        let mapper = try SchemaMapper(db: db)
        XCTAssertTrue(mapper.hasNoteData("Z_PK"))
        XCTAssertTrue(mapper.hasNoteData("ZDATA"))
        XCTAssertTrue(mapper.hasNoteData("ZNOTE"))
        XCTAssertFalse(mapper.hasNoteData("NONEXISTENT"))
    }

    func testTrashColumnDetectedWhenPresent() throws {
        let db = try fullSchemaDB()
        defer { db.close() }

        let mapper = try SchemaMapper(db: db)
        XCTAssertEqual(mapper.trashColumn, "ZISINTRASHEDBYUSER")
    }

    func testTrashColumnNilWhenMissing() throws {
        let db = try minimalSchemaDB()
        defer { db.close() }

        let mapper = try SchemaMapper(db: db)
        XCTAssertNil(mapper.trashColumn)
    }

    // MARK: - SchemaMapper: Required Column Validation

    func testThrowsIncompatibleWhenRequiredColumnMissing() throws {
        let db = try SQLiteConnection(path: ":memory:")
        defer { db.close() }

        try db.execute("CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME TEXT, Z_SUPER INTEGER, Z_MAX INTEGER)")
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (6, 'ICAccount')")
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (9, 'ICFolder')")
        try db.execute("INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (14, 'ICNote')")

        // Missing ZTITLE1 - a required column
        try db.execute("CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZIDENTIFIER TEXT)")
        try db.execute("CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZDATA BLOB)")

        do {
            _ = try SchemaMapper(db: db)
            XCTFail("Should have thrown for missing required columns")
        } catch let error as SchemaError {
            let desc = error.errorDescription ?? ""
            XCTAssertTrue(desc.contains("ZTITLE1"), "Error should mention missing column ZTITLE1, got: \(desc)")
        }
    }

    func testPassesWhenAllRequiredColumnsPresent() throws {
        let db = try minimalSchemaDB()
        defer { db.close() }

        // Should NOT throw — all required columns are in minimalSchemaDB
        let mapper = try SchemaMapper(db: db)
        XCTAssertEqual(mapper.noteEnt, 14)
    }

    // MARK: - NoteStoreDB: Query Adaptation with Full Schema

    func testListNotesWithFullSchema() throws {
        let db = try fullSchemaDB()
        defer { db.close() }

        // Insert a note
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1,
             ZSNIPPET, ZISPASSWORDPROTECTED, ZMARKEDFORDELETION, ZISINTRASHEDBYUSER, ZFOLDER)
            VALUES (1, 14, 'Test Note', 'uuid-1', 0, 0, 'A snippet', 0, 0, 0, NULL)
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let notes = try store.listNotes()

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Test Note")
        XCTAssertEqual(notes[0].snippet, "A snippet")
        XCTAssertFalse(notes[0].isPasswordProtected)
    }

    func testListNotesWithMinimalSchema() throws {
        let db = try minimalSchemaDB()
        defer { db.close() }

        // Insert a note — no ZSNIPPET, ZISPASSWORDPROTECTED, etc.
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1, ZFOLDER)
            VALUES (1, 14, 'Minimal Note', 'uuid-2', 0, 0, NULL)
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let notes = try store.listNotes()

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Minimal Note")
        XCTAssertEqual(notes[0].snippet, "")
        XCTAssertFalse(notes[0].isPasswordProtected)
    }

    func testTrashFilterExcludesWithTrashColumn() throws {
        let db = try fullSchemaDB()
        defer { db.close() }

        // Active note
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1,
             ZMARKEDFORDELETION, ZISINTRASHEDBYUSER)
            VALUES (1, 14, 'Active', 'uuid-a', 0, 0, 0, 0)
        """)
        // Trashed note
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1,
             ZMARKEDFORDELETION, ZISINTRASHEDBYUSER)
            VALUES (2, 14, 'Trashed', 'uuid-b', 0, 0, 0, 1)
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let notes = try store.listNotes()

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Active")
    }

    func testTrashFilterExcludesViaFolderType() throws {
        // Schema WITHOUT ZISINTRASHEDBYUSER, WITH ZFOLDERTYPE
        let db = try createBaseDB(mainColumns: [
            "ZSNIPPET TEXT", "ZMARKEDFORDELETION INTEGER", "ZFOLDERTYPE INTEGER",
            "ZNAME TEXT"
        ])
        defer { db.close() }

        // Create a trash folder (ZFOLDERTYPE = 1)
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE2, ZIDENTIFIER, ZFOLDERTYPE)
            VALUES (100, 9, 'Recently Deleted', 'folder-trash', 1)
        """)
        // Create a normal folder
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE2, ZIDENTIFIER, ZFOLDERTYPE)
            VALUES (101, 9, 'Notes', 'folder-notes', 0)
        """)
        // Active note in normal folder
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1,
             ZMARKEDFORDELETION, ZFOLDER)
            VALUES (1, 14, 'Active', 'uuid-a', 0, 0, 0, 101)
        """)
        // Note in trash folder
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1,
             ZMARKEDFORDELETION, ZFOLDER)
            VALUES (2, 14, 'In Trash', 'uuid-b', 0, 0, 0, 100)
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let notes = try store.listNotes()

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Active")
    }

    func testTrashFilterFallsBackToFolderName() throws {
        // Schema WITHOUT ZISINTRASHEDBYUSER AND WITHOUT ZFOLDERTYPE
        // ZTITLE2 already in base columns, just add ZMARKEDFORDELETION
        let db = try createBaseDB(mainColumns: [
            "ZMARKEDFORDELETION INTEGER", "ZNAME TEXT"
        ])
        defer { db.close() }

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)

        // Insert note — no crash is the test
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1, ZFOLDER)
            VALUES (1, 14, 'Note', 'uuid-1', 0, 0, NULL)
        """)

        let notes = try store.listNotes()
        XCTAssertEqual(notes.count, 1)
    }

    func testSearchNotesWithoutSnippet() throws {
        let db = try minimalSchemaDB()
        defer { db.close() }

        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1, ZFOLDER)
            VALUES (1, 14, 'Searchable Note', 'uuid-s', 0, 0, NULL)
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let notes = try store.searchNotes(text: "Searchable")

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Searchable Note")
    }

    func testListFoldersWithoutOptionalColumns() throws {
        // No ZPARENT, no ZACCOUNT3, no ZNAME
        let db = try minimalSchemaDB()
        defer { db.close() }

        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE2, ZIDENTIFIER)
            VALUES (1, 9, 'My Folder', 'folder-1')
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let folders = try store.listFolders()

        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].name, "My Folder")
        XCTAssertNil(folders[0].parentPK)
        XCTAssertEqual(folders[0].accountName, "")
    }

    func testListFoldersWithFullSchema() throws {
        let db = try fullSchemaDB()
        defer { db.close() }

        // Account
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZNAME, ZIDENTIFIER)
            VALUES (50, 6, 'iCloud', 'acct-1')
        """)
        // Folder with parent and account
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE2, ZIDENTIFIER, ZPARENT, ZACCOUNT3)
            VALUES (1, 9, 'Work', 'folder-1', NULL, 50)
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let folders = try store.listFolders()

        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].name, "Work")
        XCTAssertEqual(folders[0].accountName, "iCloud")
    }

    func testCreateNoteWithMinimalSchema() throws {
        let db = try minimalSchemaDB()
        defer { db.close() }

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let bodyData = Data([0x01, 0x02])

        let pk = try store.createNote(title: "New Note", bodyData: bodyData, folderPK: nil)
        XCTAssertGreaterThan(pk, 0)

        let rows = try db.query("SELECT ZTITLE1 FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?", params: [.int(pk)])
        XCTAssertEqual(rows.first?["ZTITLE1"] as? String, "New Note")
    }

    func testCreateFolderWithoutParentColumn() throws {
        let db = try minimalSchemaDB()
        defer { db.close() }

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let pk = try store.createFolder(name: "New Folder", parentPK: nil, accountPK: nil)
        XCTAssertGreaterThan(pk, 0)

        let rows = try db.query("SELECT ZTITLE2 FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?", params: [.int(pk)])
        XCTAssertEqual(rows.first?["ZTITLE2"] as? String, "New Folder")
    }

    func testDeleteFilterWithMarkedForDeletion() throws {
        let db = try createBaseDB(mainColumns: ["ZMARKEDFORDELETION INTEGER"])
        defer { db.close() }

        // Active note
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1, ZMARKEDFORDELETION, ZFOLDER)
            VALUES (1, 14, 'Active', 'uuid-a', 0, 0, 0, NULL)
        """)
        // Deleted note
        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1, ZMARKEDFORDELETION, ZFOLDER)
            VALUES (2, 14, 'Deleted', 'uuid-b', 0, 0, 1, NULL)
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let notes = try store.listNotes()

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Active")
    }

    func testDeleteFilterWithoutMarkedForDeletion() throws {
        // No ZMARKEDFORDELETION column at all
        let db = try minimalSchemaDB()
        defer { db.close() }

        try db.execute("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
            (Z_PK, Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1, ZFOLDER)
            VALUES (1, 14, 'Note', 'uuid-1', 0, 0, NULL)
        """)

        let schema = try SchemaMapper(db: db)
        let store = try NoteStoreDB(db: db, schema: schema)
        let notes = try store.listNotes()

        // Should not crash, should return the note
        XCTAssertEqual(notes.count, 1)
    }
}
