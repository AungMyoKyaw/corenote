import ArgumentParser
import Foundation
struct FolderRenameCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rename", abstract: "Rename a folder")
    @Argument(help: "Current folder name") var query: String
    @Option(name: .long, help: "New folder name") var name: String
    @Option(name: .long, help: "Custom database path") var db: String?
    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        guard let folderPK = try store.findFolderPK(byName: query) else { throw NoteStoreError.folderNotFound(name: query) }
        warnIfNotesRunning(store)
        try store.renameFolder(folderPK: folderPK, newName: name)
        print(OutputFormatter.colored("Renamed \"\(query)\" to \"\(name)\"", .green))
    }
}
