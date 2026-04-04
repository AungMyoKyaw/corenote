import ArgumentParser
import Foundation
struct FolderDeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a folder")
    @Argument(help: "Folder name") var query: String
    @Flag(name: .long, help: "Skip confirmation prompt") var force: Bool = false
    @Option(name: .long, help: "Custom database path") var db: String?
    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        guard let folderPK = try store.findFolderPK(byName: query) else { throw NoteStoreError.folderNotFound(name: query) }
        if !force { guard confirmAction("Delete folder \"\(query)\" and all its notes?") else { print("Cancelled."); return } }
        warnIfNotesRunning(store)
        try store.deleteFolder(folderPK: folderPK)
        print(OutputFormatter.colored("Deleted folder \"\(query)\"", .red))
    }
}
