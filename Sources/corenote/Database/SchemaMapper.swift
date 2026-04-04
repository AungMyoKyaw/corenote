import Foundation

enum SchemaError: Error, LocalizedError, Sendable {
    case missingEntity(String)

    var errorDescription: String? {
        switch self {
        case .missingEntity(let name):
            return "Required entity '\(name)' not found in Z_PRIMARYKEY. Database may be incompatible."
        }
    }
}

struct SchemaMapper: Sendable {
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
