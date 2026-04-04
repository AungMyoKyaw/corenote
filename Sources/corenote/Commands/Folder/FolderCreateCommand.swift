import ArgumentParser
import Foundation
struct FolderCreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new folder")
    @Argument(help: "Folder name") var name: String
    @Option(name: .long, help: "Parent folder name (for nesting)") var parent: String?
    @Option(name: .long, help: "Custom database path") var db: String?
    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        warnIfNotesRunning(store)
        var parentPK: Int64?
        if let parentName = parent {
            parentPK = try store.findFolderPK(byName: parentName)
            if parentPK == nil { throw NoteStoreError.folderNotFound(name: parentName) }
        }
        let accountPK = try store.getDefaultAccountPK()
        let pk = try store.createFolder(name: name, parentPK: parentPK, accountPK: accountPK)
        print(OutputFormatter.colored("Created folder \"\(name)\" (id: \(pk))", .green))
    }
}
