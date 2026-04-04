import Foundation

enum ANSIColor: String, Sendable {
    case red = "\u{1B}[31m"
    case green = "\u{1B}[32m"
    case yellow = "\u{1B}[33m"
    case cyan = "\u{1B}[36m"
    case white = "\u{1B}[1;37m"
    case dim = "\u{1B}[2m"
    case reset = "\u{1B}[0m"
    case bold = "\u{1B}[1m"
}

enum OutputFormatter: Sendable {
    static var isInteractive: Bool { isatty(fileno(stdout)) != 0 }

    static func colored(_ text: String, _ color: ANSIColor, forceColor: Bool? = nil) -> String {
        let useColor = forceColor ?? isInteractive
        guard useColor else { return text }
        return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
    }

    static func bold(_ text: String) -> String { colored(text, .bold) }

    static func relativeDate(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { let m = seconds / 60; return "\(m) minute\(m == 1 ? "" : "s") ago" }
        if seconds < 86400 { let h = seconds / 3600; return "\(h) hour\(h == 1 ? "" : "s") ago" }
        if seconds < 172800 { return "Yesterday" }
        if seconds < 604800 { let d = seconds / 86400; return "\(d) days ago" }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date)
    }

    static func padRight(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return text + String(repeating: " ", count: width - text.count)
    }

    static func formatNoteList(_ notes: [Note]) -> String {
        var output = ""
        let header = " \(padRight("#", width: 4))\(padRight("Title", width: 25))\(padRight("Modified", width: 18))Folder"
        output += colored(header, .dim) + "\n"
        for (i, note) in notes.enumerated() {
            let num = padRight("\(i + 1)", width: 4)
            let title = padRight(String(note.title.prefix(23)), width: 25)
            let modified = padRight(relativeDate(note.modifiedAt), width: 18)
            let folder = colored(note.folderName, .cyan)
            output += " \(num)\(colored(title, .white))  \(colored(modified, .yellow))  \(folder)\n"
        }
        output += colored("\n\(notes.count) note\(notes.count == 1 ? "" : "s")", .dim)
        return output
    }

    static func formatNoteDetail(note: Note, body: String) -> String {
        var output = ""
        output += "\n\(colored(note.title, .white))\n"
        output += colored(String(repeating: "\u{2550}", count: 40), .dim) + "\n"
        let meta = [
            "\(colored("Folder:", .dim)) \(colored(note.folderName, .cyan))",
            "\(colored("Modified:", .dim)) \(colored(relativeDate(note.modifiedAt), .yellow))",
            "\(colored("Created:", .dim)) \(colored(relativeDate(note.createdAt), .yellow))",
        ].joined(separator: "  \(colored("\u{2502}", .dim))  ")
        output += meta + "\n\n" + body + "\n"
        return output
    }

    static func formatFolderList(_ folders: [Folder]) -> String {
        var output = ""
        let header = " \(padRight("Folder", width: 20))\(padRight("Notes", width: 8))Account"
        output += colored(header, .dim) + "\n"
        for folder in folders {
            let name = padRight(String(folder.name.prefix(18)), width: 20)
            let count = padRight("\(folder.noteCount)", width: 8)
            output += " \(colored(name, .cyan))\(count)\(folder.accountName)\n"
        }
        return output
    }

    static func formatSearchResults(_ notes: [Note], query: String) -> String {
        var output = ""
        let header = " \(padRight("#", width: 4))\(padRight("Title", width: 20))\(padRight("Folder", width: 14))Match"
        output += colored(header, .dim) + "\n"
        for (i, note) in notes.enumerated() {
            let num = padRight("\(i + 1)", width: 4)
            let title = padRight(String(note.title.prefix(18)), width: 20)
            let folder = padRight(note.folderName, width: 14)
            let snippet = highlightMatch(note.snippet, query: query)
            output += " \(num)\(colored(title, .white))\(colored(folder, .cyan))\(snippet)\n"
        }
        output += colored("\n\(notes.count) note\(notes.count == 1 ? "" : "s") matched \"\(query)\"", .dim)
        return output
    }

    private static func highlightMatch(_ text: String, query: String) -> String {
        guard let range = text.lowercased().range(of: query.lowercased()) else {
            return colored("\"...\(String(text.prefix(30)))...\"", .dim)
        }
        let start = max(text.startIndex, text.index(range.lowerBound, offsetBy: -15, limitedBy: text.startIndex) ?? text.startIndex)
        let end = min(text.endIndex, text.index(range.upperBound, offsetBy: 15, limitedBy: text.endIndex) ?? text.endIndex)
        return colored("\"...\(text[start..<end])...\"", .dim)
    }
}
