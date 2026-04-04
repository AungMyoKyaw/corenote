import ArgumentParser
import Foundation

struct CreateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new note")

    @Option(name: .long, help: "Note title")
    var title: String?

    @Option(name: .long, help: "Note body (Markdown)")
    var body: String?

    @Option(name: .long, help: "Target folder (default: Notes)")
    var folder: String?

    @Flag(name: .long, help: "Open in $EDITOR")
    var editor: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        warnIfNotesRunning(store)
        var noteTitle: String
        var noteBody: String
        if editor {
            let template = "# \(title ?? "Untitled")\n\n"
            let edited = try EditorLauncher.edit(content: template, filename: "corenote-new.md")
            let lines = edited.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            noteTitle = String(lines.first ?? "Untitled")
            if noteTitle.hasPrefix("# ") { noteTitle = String(noteTitle.dropFirst(2)) }
            noteBody = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        } else {
            guard let t = title else { throw ValidationError("--title is required (or use --editor)") }
            noteTitle = t
            noteBody = body ?? ""
        }
        let markdown = noteBody.isEmpty ? noteTitle + "\n" : "# \(noteTitle)\n\(noteBody)\n"
        let decoded = MarkdownToNote.convert(markdown)
        let encoded = try NoteBodyEncoder.encode(decoded)
        let folderPK: Int64?
        if let folderName = folder {
            folderPK = try store.findFolderPK(byName: folderName)
            if folderPK == nil { throw NoteStoreError.folderNotFound(name: folderName) }
        } else {
            folderPK = try store.findFolderPK(byName: "Notes")
        }
        let pk = try store.createNote(title: noteTitle, bodyData: encoded, folderPK: folderPK)
        print(OutputFormatter.colored("Created note \"\(noteTitle)\" (id: \(pk))", .green))
    }
}
