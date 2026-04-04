import ArgumentParser
import Foundation

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all notes"
    )

    @Option(name: .long, help: "Filter by folder name")
    var folder: String?

    @Option(name: .long, help: "Filter by account name")
    var account: String?

    @Option(name: .long, help: "Maximum number of results")
    var limit: Int = 50

    @Option(name: .long, help: "Sort by: modified, created, or title")
    var sort: String = "modified"

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let notes = try store.listNotes(folder: folder, account: account, limit: limit, sort: sort)
        if json {
            print(try JSONOutput.serializeNotes(notes))
        } else {
            print(OutputFormatter.formatNoteList(notes))
        }
    }
}
