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

        try db.execute("""
            CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER,
                ZTITLE1 TEXT, ZTITLE2 TEXT, ZIDENTIFIER TEXT,
                ZCREATIONDATE1 REAL, ZMODIFICATIONDATE1 REAL,
                ZFOLDER INTEGER, ZNOTEDATA INTEGER
            )
        """)
        try db.execute("CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZDATA BLOB, ZNOTE INTEGER)")

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
