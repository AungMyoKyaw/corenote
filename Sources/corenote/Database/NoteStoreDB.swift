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
