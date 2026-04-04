import ArgumentParser
import Foundation

struct MoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "move", abstract: "Move a note to another folder")

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
        guard let folderPK = try store.findFolderPK(byName: to) else { throw NoteStoreError.folderNotFound(name: to) }
        warnIfNotesRunning(store)
        try store.moveNote(notePK: note.pk, toFolderPK: folderPK)
        print(OutputFormatter.colored("Moved \"\(note.title)\" to \(to)", .green))
    }
}
