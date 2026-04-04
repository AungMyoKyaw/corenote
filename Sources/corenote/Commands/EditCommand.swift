import ArgumentParser
import Foundation

struct EditCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "edit", abstract: "Edit an existing note")

    @Argument(help: "Note title (fuzzy match) or ID")
    var query: String

    @Flag(name: .long, help: "Treat query as internal ID")
    var id: Bool = false

    @Option(name: .long, help: "Replace body with this text (Markdown)")
    var body: String?

    @Option(name: .long, help: "Update title")
    var title: String?

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let note = try resolveNote(query: query, useID: id, store: store)
        if note.isPasswordProtected { throw ValidationError("Note \"\(note.title)\" is encrypted — cannot edit") }
        warnIfNotesRunning(store)
        if let newBody = body {
            let markdown = "# \(title ?? note.title)\n\(newBody)\n"
            let decoded = MarkdownToNote.convert(markdown)
            let encoded = try NoteBodyEncoder.encode(decoded)
            try store.updateNoteBody(notePK: note.pk, bodyData: encoded, title: title)
            print(OutputFormatter.colored("Updated \"\(title ?? note.title)\"", .green))
        } else {
            guard let bodyData = try store.getNoteBody(notePK: note.pk) else {
                throw ValidationError("Cannot read note body for \"\(note.title)\"")
            }
            let decoded = try NoteBodyDecoder.decode(data: bodyData)
            let originalMarkdown = NoteToMarkdown.convert(decoded)
            let edited = try EditorLauncher.edit(content: originalMarkdown, filename: "corenote-\(note.pk).md")
            if edited.trimmingCharacters(in: .whitespacesAndNewlines) == originalMarkdown.trimmingCharacters(in: .whitespacesAndNewlines) {
                print("No changes made."); return
            }
            let newDecoded = MarkdownToNote.convert(edited)
            let encoded = try NoteBodyEncoder.encode(newDecoded)
            var newTitle = title
            if newTitle == nil {
                let firstLine = edited.split(separator: "\n").first.map(String.init) ?? note.title
                if firstLine.hasPrefix("# ") { newTitle = String(firstLine.dropFirst(2)) }
            }
            try store.updateNoteBody(notePK: note.pk, bodyData: encoded, title: newTitle)
            print(OutputFormatter.colored("Updated \"\(newTitle ?? note.title)\"", .green))
        }
    }
}
