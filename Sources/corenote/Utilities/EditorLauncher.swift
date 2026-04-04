import Foundation

enum EditorError: Error, LocalizedError, Sendable {
    case noEditorFound
    case editorFailed(Int32)
    var errorDescription: String? {
        switch self {
        case .noEditorFound: return "No editor found. Set $EDITOR environment variable."
        case .editorFailed(let code): return "Editor exited with code \(code)"
        }
    }
}

enum EditorLauncher: Sendable {
    static func edit(content: String, filename: String = "corenote-temp.md") throws -> String {
        let tempPath = NSTemporaryDirectory() + filename
        try content.write(toFile: tempPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        guard let editor = findEditor() else { throw EditorError.noEditorFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, tempPath]
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { throw EditorError.editorFailed(process.terminationStatus) }
        return try String(contentsOfFile: tempPath, encoding: .utf8)
    }

    private static func findEditor() -> String? {
        if let editor = ProcessInfo.processInfo.environment["EDITOR"], !editor.isEmpty { return editor }
        for candidate in ["vim", "nano", "vi"] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            p.arguments = [candidate]
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            try? p.run(); p.waitUntilExit()
            if p.terminationStatus == 0 { return candidate }
        }
        return nil
    }
}
