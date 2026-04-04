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
