import Foundation

enum NoteStoreError: Error, LocalizedError, Sendable {
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

final class NoteStoreDB: @unchecked Sendable {
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

    init(db: SQLiteConnection, schema: SchemaMapper) {
        self.db = db
        self.schema = schema
    }

    // MARK: - Query Helpers

    private func optionalCol(_ alias: String, _ column: String, fallback: String? = nil) -> String {
        if schema.has(column) {
            return ", \(alias).\(column)"
        } else if let fb = fallback {
            return ", \(fb) as \(column)"
        }
        return ""
    }

    private func deletionFilter(_ alias: String) -> String {
        if schema.has("ZMARKEDFORDELETION") {
            return "AND (\(alias).ZMARKEDFORDELETION != 1 OR \(alias).ZMARKEDFORDELETION IS NULL)"
        }
        return ""
    }

    private func trashFilter(_ alias: String) -> String {
        if let col = schema.trashColumn {
            return "AND (\(alias).\(col) != 1 OR \(alias).\(col) IS NULL)"
        }
        if schema.has("ZFOLDERTYPE") {
            return "AND (\(alias).ZFOLDER IS NULL OR (SELECT ZFOLDERTYPE FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = \(alias).ZFOLDER) != 1)"
        }
        return ""
    }

    private func accountJoin(noteAlias: String) -> String {
        if schema.has("ZACCOUNT2") && schema.has("ZNAME") {
            return "LEFT JOIN ZICCLOUDSYNCINGOBJECT a ON a.Z_PK = \(noteAlias).ZACCOUNT2"
        }
        return ""
    }

    private func accountSelect() -> String {
        if schema.has("ZACCOUNT2") && schema.has("ZNAME") {
            return ", a.ZNAME as account_name"
        }
        return ""
    }

    private func folderAccountJoin(folderAlias: String) -> String {
        if schema.has("ZACCOUNT3") && schema.has("ZNAME") {
            return "LEFT JOIN ZICCLOUDSYNCINGOBJECT a ON a.Z_PK = \(folderAlias).ZACCOUNT3"
        }
        return ""
    }

    private func folderAccountSelect() -> String {
        if schema.has("ZACCOUNT3") && schema.has("ZNAME") {
            return ", a.ZNAME as account_name"
        }
        return ""
    }

    // MARK: - Read Operations

    func listNotes(folder: String? = nil, account: String? = nil,
                   limit: Int = 50, sort: String = "modified") throws -> [Note] {
        var sql = """
            SELECT c.Z_PK, c.ZTITLE1, c.ZIDENTIFIER,
                   c.ZCREATIONDATE1, c.ZMODIFICATIONDATE1\(optionalCol("c", "ZSNIPPET"))\(optionalCol("c", "ZISPASSWORDPROTECTED")),
                   f.ZTITLE2 as folder_name\(accountSelect())
            FROM ZICCLOUDSYNCINGOBJECT c
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON f.Z_PK = c.ZFOLDER
            \(accountJoin(noteAlias: "c"))
            WHERE c.Z_ENT = ?
              \(deletionFilter("c"))
              \(trashFilter("c"))
        """
        var params: [SQLiteParam] = [.int(schema.noteEnt)]

        if let folder = folder {
            sql += " AND f.ZTITLE2 = ?"
            params.append(.text(folder))
        }
        if let account = account, schema.has("ZNAME") {
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
        let hasSnippet = schema.has("ZSNIPPET")
        let snippetMatch = hasSnippet ? " OR c.ZSNIPPET LIKE ?" : ""

        var sql = """
            SELECT c.Z_PK, c.ZTITLE1, c.ZIDENTIFIER,
                   c.ZCREATIONDATE1, c.ZMODIFICATIONDATE1\(optionalCol("c", "ZSNIPPET"))\(optionalCol("c", "ZISPASSWORDPROTECTED")),
                   f.ZTITLE2 as folder_name\(accountSelect())
            FROM ZICCLOUDSYNCINGOBJECT c
            LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON f.Z_PK = c.ZFOLDER
            \(accountJoin(noteAlias: "c"))
            LEFT JOIN ZICNOTEDATA n ON c.ZNOTEDATA = n.Z_PK
            WHERE c.Z_ENT = ?
              \(deletionFilter("c"))
              \(trashFilter("c"))
              AND (c.ZTITLE1 LIKE ?\(snippetMatch))
        """
        let pattern = "%\(text)%"
        var params: [SQLiteParam] = [.int(schema.noteEnt), .text(pattern)]
        if hasSnippet {
            params.append(.text(pattern))
        }

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
        let hasParent = schema.has("ZPARENT")
        let parentSelect = hasParent ? ", f.ZPARENT" : ""

        var sql = """
            SELECT f.Z_PK, f.ZTITLE2, f.ZIDENTIFIER\(parentSelect)\(folderAccountSelect()),
                   (SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT n
                    WHERE n.ZFOLDER = f.Z_PK AND n.Z_ENT = ?
                    \(deletionFilter("n"))
                    \(trashFilter("n"))
                   ) as note_count
            FROM ZICCLOUDSYNCINGOBJECT f
            \(folderAccountJoin(folderAlias: "f"))
            WHERE f.Z_ENT = ?
        """
        var params: [SQLiteParam] = [.int(schema.noteEnt), .int(schema.folderEnt)]

        if let account = account, schema.has("ZNAME") {
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
        let isTrashed: Bool
        if let col = schema.trashColumn, let val = row[col] as? Int64 {
            isTrashed = val == 1
        } else {
            isTrashed = folderName == "Recently Deleted"
        }
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

// MARK: - Write operations
extension NoteStoreDB {
    func createNote(title: String, bodyData: Data, folderPK: Int64?) throws -> Int64 {
        let now = Note.macFromDate(Date())
        let uuid = UUID().uuidString

        var cols = "Z_ENT, ZTITLE1, ZIDENTIFIER, ZCREATIONDATE1, ZMODIFICATIONDATE1, ZFOLDER"
        var placeholders = "?, ?, ?, ?, ?, ?"
        var params: [SQLiteParam] = [
            .int(schema.noteEnt), .text(title), .text(uuid),
            .double(now), .double(now), folderPK.map { .int($0) } ?? .null
        ]

        if schema.has("ZMARKEDFORDELETION") {
            cols += ", ZMARKEDFORDELETION"
            placeholders += ", 0"
        }
        if let trashCol = schema.trashColumn {
            cols += ", \(trashCol)"
            placeholders += ", 0"
        }

        try db.execute(
            "INSERT INTO ZICCLOUDSYNCINGOBJECT (\(cols)) VALUES (\(placeholders))",
            params: params
        )
        let noteRows = try db.query("SELECT last_insert_rowid() as pk")
        guard let notePK = noteRows.first?["pk"] as? Int64 else { throw NoteStoreError.noteNotFound(query: title) }

        try db.execute("INSERT INTO ZICNOTEDATA (ZNOTE, ZDATA) VALUES (?, ?)",
            params: [.int(notePK), .blob(bodyData)])
        let dataRows = try db.query("SELECT last_insert_rowid() as pk")
        guard let dataPK = dataRows.first?["pk"] as? Int64 else { throw NoteStoreError.noteNotFound(query: title) }

        try db.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZNOTEDATA = ? WHERE Z_PK = ?",
            params: [.int(dataPK), .int(notePK)])
        return notePK
    }

    func updateNoteBody(notePK: Int64, bodyData: Data, title: String? = nil) throws {
        let now = Note.macFromDate(Date())
        try db.execute("UPDATE ZICNOTEDATA SET ZDATA = ? WHERE Z_PK = (SELECT ZNOTEDATA FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?)",
            params: [.blob(bodyData), .int(notePK)])
        if let title = title {
            try db.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZMODIFICATIONDATE1 = ?, ZTITLE1 = ? WHERE Z_PK = ?",
                params: [.double(now), .text(title), .int(notePK)])
        } else {
            try db.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZMODIFICATIONDATE1 = ? WHERE Z_PK = ?",
                params: [.double(now), .int(notePK)])
        }
    }

    func trashNote(notePK: Int64) throws {
        let now = Note.macFromDate(Date())
        if let col = schema.trashColumn {
            try db.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET \(col) = 1, ZMODIFICATIONDATE1 = ? WHERE Z_PK = ?",
                params: [.double(now), .int(notePK)])
        } else if schema.has("ZMARKEDFORDELETION") {
            try db.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZMARKEDFORDELETION = 1, ZMODIFICATIONDATE1 = ? WHERE Z_PK = ?",
                params: [.double(now), .int(notePK)])
        }
    }

    func permanentlyDeleteNote(notePK: Int64) throws {
        try db.execute("DELETE FROM ZICNOTEDATA WHERE Z_PK = (SELECT ZNOTEDATA FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?)",
            params: [.int(notePK)])
        try db.execute("DELETE FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ?", params: [.int(notePK)])
    }

    func moveNote(notePK: Int64, toFolderPK: Int64) throws {
        let now = Note.macFromDate(Date())
        try db.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZFOLDER = ?, ZMODIFICATIONDATE1 = ? WHERE Z_PK = ?",
            params: [.int(toFolderPK), .double(now), .int(notePK)])
    }

    func createFolder(name: String, parentPK: Int64?, accountPK: Int64?) throws -> Int64 {
        let uuid = UUID().uuidString

        var cols = "Z_ENT, ZTITLE2, ZIDENTIFIER"
        var placeholders = "?, ?, ?"
        var params: [SQLiteParam] = [.int(schema.folderEnt), .text(name), .text(uuid)]

        if schema.has("ZPARENT") {
            cols += ", ZPARENT"
            placeholders += ", ?"
            params.append(parentPK.map { .int($0) } ?? .null)
        }
        if schema.has("ZACCOUNT3") {
            cols += ", ZACCOUNT3"
            placeholders += ", ?"
            params.append(accountPK.map { .int($0) } ?? .null)
        }

        try db.execute(
            "INSERT INTO ZICCLOUDSYNCINGOBJECT (\(cols)) VALUES (\(placeholders))",
            params: params
        )
        let rows = try db.query("SELECT last_insert_rowid() as pk")
        return rows.first?["pk"] as? Int64 ?? 0
    }

    func renameFolder(folderPK: Int64, newName: String) throws {
        try db.execute("UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE2 = ? WHERE Z_PK = ? AND Z_ENT = ?",
            params: [.text(newName), .int(folderPK), .int(schema.folderEnt)])
    }

    func deleteFolder(folderPK: Int64) throws {
        try db.execute("DELETE FROM ZICCLOUDSYNCINGOBJECT WHERE Z_PK = ? AND Z_ENT = ?",
            params: [.int(folderPK), .int(schema.folderEnt)])
    }

    func getDefaultAccountPK() throws -> Int64? {
        let rows = try db.query("SELECT Z_PK FROM ZICCLOUDSYNCINGOBJECT WHERE Z_ENT = ? LIMIT 1",
            params: [.int(schema.accountEnt)])
        return rows.first?["Z_PK"] as? Int64
    }
}
