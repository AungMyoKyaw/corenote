import XCTest
import Foundation
@testable import corenote

final class NoteBodyDecoderTests: XCTestCase {
    func testDecodeUncompressedProtobuf() throws {
        var note = CNNote()
        note.noteText = "Hello World"
        var run = CNAttributeRun()
        run.length = 11
        note.attributeRun = [run]
        var doc = CNDocument()
        doc.version = 0
        doc.note = note
        var proto = CNNoteStoreProto()
        proto.document = doc
        let data = try proto.serializedData()

        let decoded = try NoteBodyDecoder.decode(data: data)
        XCTAssertEqual(decoded.text, "Hello World")
        XCTAssertEqual(decoded.runs.count, 1)
        XCTAssertEqual(decoded.runs[0].length, 11)
    }

    func testDecodeGzippedProtobuf() throws {
        var note = CNNote()
        note.noteText = "Compressed note"
        var run = CNAttributeRun()
        run.length = 15
        note.attributeRun = [run]
        var doc = CNDocument()
        doc.note = note
        var proto = CNNoteStoreProto()
        proto.document = doc
        let raw = try proto.serializedData()
        let gzipped = try GzipHelper.compress(raw)

        let decoded = try NoteBodyDecoder.decode(data: gzipped)
        XCTAssertEqual(decoded.text, "Compressed note")
    }

    func testDecodeWithFormattingRuns() throws {
        var note = CNNote()
        note.noteText = "Title\nBold text"
        var titleRun = CNAttributeRun()
        titleRun.length = 6
        var titleStyle = CNParagraphStyle()
        titleStyle.styleType = 1
        titleRun.paragraphStyle = titleStyle
        var boldRun = CNAttributeRun()
        boldRun.length = 9
        boldRun.fontWeight = 1
        note.attributeRun = [titleRun, boldRun]
        var doc = CNDocument()
        doc.note = note
        var proto = CNNoteStoreProto()
        proto.document = doc
        let data = try proto.serializedData()

        let decoded = try NoteBodyDecoder.decode(data: data)
        XCTAssertEqual(decoded.runs.count, 2)
        XCTAssertEqual(decoded.runs[0].paragraphStyle?.styleType, .heading1)
        XCTAssertTrue(decoded.runs[1].isBold)
    }

    func testDecodeEncryptedDataThrows() {
        let notGzipped = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try NoteBodyDecoder.decode(data: notGzipped))
    }
}
