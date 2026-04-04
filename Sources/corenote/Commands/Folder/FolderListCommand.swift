import ArgumentParser
import Foundation
struct FolderListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List all folders")
    @Option(name: .long, help: "Filter by account name") var account: String?
    @Flag(name: .long, help: "Output as JSON") var json: Bool = false
    @Option(name: .long, help: "Custom database path") var db: String?
    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let folders = try store.listFolders(account: account)
        if json { print(try JSONOutput.serializeFolders(folders)) }
        else { print(OutputFormatter.formatFolderList(folders)) }
    }
}
