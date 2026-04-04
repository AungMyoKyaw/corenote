import Foundation
import Compression

// MARK: - GzipHelper

enum GzipHelper: Sendable {
    private static let gzipMagicByte1: UInt8 = 0x1F
    private static let gzipMagicByte2: UInt8 = 0x8B

    static func isGzipped(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[data.startIndex] == gzipMagicByte1
            && data[data.startIndex + 1] == gzipMagicByte2
    }

    static func decompress(_ data: Data) throws -> Data {
        guard isGzipped(data) else {
            throw GzipError.notGzipped
        }
        return try processWithGzip(data: data, decompress: true)
    }

    static func compress(_ data: Data) throws -> Data {
        return try processWithGzip(data: data, decompress: false)
    }

    private static func processWithGzip(data: Data, decompress: Bool) throws -> Data {
        let tempIn = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let tempOut = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        defer {
            try? FileManager.default.removeItem(at: tempIn)
            try? FileManager.default.removeItem(at: tempOut)
        }

        try data.write(to: tempIn)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: decompress ? "/usr/bin/gunzip" : "/usr/bin/gzip")
        if decompress {
            process.arguments = ["-c", tempIn.path]
        } else {
            process.arguments = ["-c", tempIn.path]
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            throw GzipError.processFailed(exitCode: process.terminationStatus)
        }

        return outputData
    }

    enum GzipError: Error, Sendable {
        case notGzipped
        case processFailed(exitCode: Int32)
    }
}

// MARK: - Decoded Types

struct DecodedNoteBody: Sendable {
    let text: String
    let runs: [DecodedRun]
}

struct DecodedRun: Sendable {
    let length: Int
    let paragraphStyle: DecodedParagraphStyle?
    let isBold: Bool
    let isUnderlined: Bool
    let isStrikethrough: Bool
    let link: String?
    let attachment: DecodedAttachment?

    struct DecodedParagraphStyle: Sendable {
        enum StyleType: Int, Sendable {
            case title = 0
            case heading1 = 1
            case heading2 = 2
            case heading3 = 3
        }
        let styleType: StyleType?
        let listStyle: Int?    // 100 = bullet, 200 = numbered
        let isChecklist: Bool
        let isChecklistDone: Bool
        let isBlockquote: Bool
        let indentAmount: Int
    }

    struct DecodedAttachment: Sendable {
        let identifier: String
        let typeUTI: String
    }
}

// MARK: - NoteBodyDecoder

enum NoteBodyDecoder: Sendable {
    enum DecodeError: Error, Sendable {
        case invalidData
        case decodeFailed(String)
    }

    static func decode(data: Data) throws -> DecodedNoteBody {
        // If gzipped, decompress first
        let protoData: Data
        if GzipHelper.isGzipped(data) {
            protoData = try GzipHelper.decompress(data)
        } else {
            protoData = data
        }

        // Parse as CNNoteStoreProto (protobuf)
        let proto: CNNoteStoreProto
        do {
            proto = try CNNoteStoreProto(serializedBytes: protoData)
        } catch {
            throw DecodeError.decodeFailed("Protobuf parse failed: \(error)")
        }

        let note = proto.document.note

        // Extract text
        let text = note.noteText

        // Convert attribute runs
        let runs: [DecodedRun] = note.attributeRun.map { run in
            convertRun(run)
        }

        return DecodedNoteBody(text: text, runs: runs)
    }

    private static func convertRun(_ run: CNAttributeRun) -> DecodedRun {
        let paragraphStyle: DecodedRun.DecodedParagraphStyle? = run.hasParagraphStyle
            ? convertParagraphStyle(run.paragraphStyle)
            : nil

        let isBold = run.hasFontWeight && run.fontWeight != 0
        let isUnderlined = run.hasUnderlined && run.underlined != 0
        let isStrikethrough = run.hasStrikethrough && run.strikethrough != 0
        let link: String? = run.hasLink ? run.link : nil

        let attachment: DecodedRun.DecodedAttachment?
        if run.hasAttachmentInfo {
            attachment = DecodedRun.DecodedAttachment(
                identifier: run.attachmentInfo.attachmentIdentifier,
                typeUTI: run.attachmentInfo.typeUti
            )
        } else {
            attachment = nil
        }

        return DecodedRun(
            length: Int(run.length),
            paragraphStyle: paragraphStyle,
            isBold: isBold,
            isUnderlined: isUnderlined,
            isStrikethrough: isStrikethrough,
            link: link,
            attachment: attachment
        )
    }

    private static func convertParagraphStyle(
        _ style: CNParagraphStyle
    ) -> DecodedRun.DecodedParagraphStyle {
        let styleType: DecodedRun.DecodedParagraphStyle.StyleType?
        if style.hasStyleType {
            styleType = DecodedRun.DecodedParagraphStyle.StyleType(rawValue: Int(style.styleType))
        } else {
            styleType = nil
        }

        let listStyle: Int? = style.hasListStyle ? Int(style.listStyle) : nil

        let isChecklist = style.hasChecklist
        let isChecklistDone = style.hasChecklist && style.checklist.done != 0
        let isBlockquote = style.hasBlockquote && style.blockquote != 0
        let indentAmount = Int(style.indentAmount)

        return DecodedRun.DecodedParagraphStyle(
            styleType: styleType,
            listStyle: listStyle,
            isChecklist: isChecklist,
            isChecklistDone: isChecklistDone,
            isBlockquote: isBlockquote,
            indentAmount: indentAmount
        )
    }
}
