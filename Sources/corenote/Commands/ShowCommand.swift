import ArgumentParser
import Foundation

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a note's content"
    )

    @Argument(help: "Note title (fuzzy match) or ID")
    var query: String

    @Flag(name: .long, help: "Treat query as internal ID")
    var id: Bool = false

    @Flag(name: .long, help: "Show raw plain text (no Markdown rendering)")
    var raw: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Custom database path")
    var db: String?

    mutating func run() throws {
        let store = try NoteStoreDB(path: db)
        let note = try resolveNote(query: query, useID: id, store: store)

        if note.isPasswordProtected {
            throw ValidationError("Note \"\(note.title)\" is encrypted — cannot read")
        }

        guard let bodyData = try store.getNoteBody(notePK: note.pk) else {
            if json {
                print(try JSONOutput.serializeNote(note, body: "(empty note)"))
            } else {
                print(OutputFormatter.formatNoteDetail(note: note, body: "(empty note)"))
            }
            return
        }

        let decoded = try NoteBodyDecoder.decode(data: bodyData)

        if raw {
            if json {
                print(try JSONOutput.serializeNote(note, body: decoded.text))
            } else {
                print(decoded.text)
            }
        } else {
            let markdown = NoteToMarkdown.convert(decoded)
            if json {
                print(try JSONOutput.serializeNote(note, body: markdown))
            } else {
                print(OutputFormatter.formatNoteDetail(note: note, body: markdown))
            }
        }
    }
}

// Free function used by show, edit, delete, move commands
func resolveNote(query: String, useID: Bool, store: NoteStoreDB) throws -> Note {
    if useID {
        if let pk = Int64(query) {
            let notes = try store.listNotes(limit: Int.max)
            if let note = notes.first(where: { $0.pk == pk }) { return note }
        }
        if let pk = try store.findNotePK(byUUID: query) {
            let notes = try store.listNotes(limit: Int.max)
            if let note = notes.first(where: { $0.pk == pk }) { return note }
        }
        throw NoteStoreError.noteNotFound(query: query)
    }

    let allNotes = try store.listNotes(limit: Int.max)
    let titles = allNotes.map { $0.title }
    let matches = FuzzyMatcher.match(query: query, candidates: titles)

    if matches.isEmpty { throw NoteStoreError.noteNotFound(query: query) }
    if matches.count == 1 { return allNotes.first { $0.title == matches[0] }! }

    if matches.count <= 5 {
        print("Multiple notes match \"\(query)\":")
        for (i, title) in matches.enumerated() { print("  \(i + 1). \(title)") }
        print("Enter number (1-\(matches.count)): ", terminator: "")
        guard let input = readLine(), let choice = Int(input),
              choice >= 1, choice <= matches.count else {
            throw ValidationError("Invalid selection")
        }
        return allNotes.first { $0.title == matches[choice - 1] }!
    }

    print("Too many matches for \"\(query)\". Showing first 10:")
    for title in matches.prefix(10) { print("  - \(title)") }
    throw ValidationError("Please narrow your search query")
}

// Free functions used by write commands
func warnIfNotesRunning(_ store: NoteStoreDB) {
    if store.isNotesAppRunning() {
        print(OutputFormatter.colored(
            "Warning: Notes.app is running. Changes may conflict with sync.", .yellow))
    }
}

func confirmAction(_ prompt: String) -> Bool {
    print("\(prompt) [y/N] ", terminator: "")
    guard let input = readLine()?.lowercased() else { return false }
    return input == "y" || input == "yes"
}
