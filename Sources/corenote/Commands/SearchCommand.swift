import ArgumentParser
import Foundation

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Full-text search across notes"
    )

    @Argument(help: "Search text")
    var text: String

    @Option(name: .long, help: "Limit search to folder")
    var folder: String?

    @Option(name: .long, help: "Maximum number of results")
    var limit: Int = 50

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let notes = try store.searchNotes(text: text, folder: folder, limit: limit)
        if json {
            print(try JSONOutput.serializeNotes(notes))
        } else {
            print(OutputFormatter.formatSearchResults(notes, query: text))
        }
    }
}
