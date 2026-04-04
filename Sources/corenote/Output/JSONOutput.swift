import Foundation

enum JSONOutput: Sendable {
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func noteToJSON(_ note: Note, body: String? = nil) -> [String: Any] {
        var dict: [String: Any] = [
            "id": note.pk, "uuid": note.uuid, "title": note.title,
            "snippet": note.snippet, "folder": note.folderName,
            "account": note.accountName,
            "created": isoFormatter.string(from: note.createdAt),
            "modified": isoFormatter.string(from: note.modifiedAt),
            "trashed": note.isTrashed,
        ]
        if let body = body { dict["body"] = body }
        return dict
    }

    static func folderToJSON(_ folder: Folder) -> [String: Any] {
        ["id": folder.pk, "uuid": folder.uuid, "name": folder.name,
         "account": folder.accountName, "noteCount": folder.noteCount]
    }

    static func serialize(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func serializeNotes(_ notes: [Note]) throws -> String { try serialize(notes.map { noteToJSON($0) }) }
    static func serializeFolders(_ folders: [Folder]) throws -> String { try serialize(folders.map { folderToJSON($0) }) }
    static func serializeNote(_ note: Note, body: String? = nil) throws -> String { try serialize(noteToJSON(note, body: body)) }
}
