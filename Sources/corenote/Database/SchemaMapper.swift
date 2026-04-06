import Foundation

enum SchemaError: Error, LocalizedError, Sendable {
    case missingEntity(String)
    case incompatibleDatabase(missing: [String])

    var errorDescription: String? {
        switch self {
        case .missingEntity(let name):
            return "Required entity '\(name)' not found in Z_PRIMARYKEY. Database may be incompatible."
        case .incompatibleDatabase(let missing):
            return "Incompatible database: missing required columns: \(missing.joined(separator: ", ")). Your macOS version may require a different corenote version."
        }
    }
}

struct SchemaMapper: Sendable {
    let noteEnt: Int64
    let folderEnt: Int64
    let accountEnt: Int64
    let trashColumn: String?

    private let mainColumns: Set<String>
    private let noteDataColumns: Set<String>

    static let requiredMainColumns: Set<String> = [
        "Z_PK", "Z_ENT", "ZTITLE1", "ZIDENTIFIER",
        "ZFOLDER", "ZNOTEDATA", "ZCREATIONDATE1", "ZMODIFICATIONDATE1"
    ]

    static let requiredNoteDataColumns: Set<String> = [
        "Z_PK", "ZDATA"
    ]

    func has(_ column: String) -> Bool {
        mainColumns.contains(column)
    }

    func hasNoteData(_ column: String) -> Bool {
        noteDataColumns.contains(column)
    }

    init(db: SQLiteConnection) throws {
        // Discover entity types
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

        // Detect main table columns
        let mainCols = try db.query("PRAGMA table_info(ZICCLOUDSYNCINGOBJECT)")
        self.mainColumns = Set(mainCols.compactMap { $0["name"] as? String })

        // Detect note data table columns
        let ndCols = try db.query("PRAGMA table_info(ZICNOTEDATA)")
        self.noteDataColumns = Set(ndCols.compactMap { $0["name"] as? String })

        // Validate required columns
        let missingMain = Self.requiredMainColumns.subtracting(self.mainColumns)
        let missingND = Self.requiredNoteDataColumns.subtracting(self.noteDataColumns)
        let allMissing = missingMain.union(missingND).sorted()
        if !allMissing.isEmpty {
            throw SchemaError.incompatibleDatabase(missing: allMissing)
        }

        // Detect trash column
        if self.mainColumns.contains("ZISINTRASHEDBYUSER") {
            self.trashColumn = "ZISINTRASHEDBYUSER"
        } else {
            self.trashColumn = nil
        }
    }
}
