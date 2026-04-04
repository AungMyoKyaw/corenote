import ArgumentParser
import Foundation

struct DeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Move a note to Recently Deleted")

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
            if !force { guard confirmAction("PERMANENTLY delete \"\(note.title)\"? This cannot be undone.") else { print("Cancelled."); return } }
            try store.permanentlyDeleteNote(notePK: note.pk)
            print(OutputFormatter.colored("Permanently deleted \"\(note.title)\"", .red))
        } else {
            if !force { guard confirmAction("Delete \"\(note.title)\"? This moves it to Recently Deleted.") else { print("Cancelled."); return } }
            try store.trashNote(notePK: note.pk)
            print(OutputFormatter.colored("Moved \"\(note.title)\" to Recently Deleted", .yellow))
        }
    }
}
