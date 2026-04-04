import XCTest
@testable import corenote

final class NoteBodyEncoderTests: XCTestCase {
    func testEncodeAndDecodeRoundTrip() throws {
        let body = DecodedNoteBody(
            text: "Hello World\n",
            runs: [DecodedRun(length: 12, paragraphStyle: nil, isBold: false,
                              isUnderlined: false, isStrikethrough: false,
                              link: nil, attachment: nil)]
        )
        let encoded = try NoteBodyEncoder.encode(body)
        XCTAssertTrue(GzipHelper.isGzipped(encoded))
        let decoded = try NoteBodyDecoder.decode(data: encoded)
        XCTAssertEqual(decoded.text, "Hello World\n")
        XCTAssertEqual(decoded.runs.count, 1)
    }

    func testEncodeWithFormatting() throws {
        let body = DecodedNoteBody(
            text: "Title\nBold text\n",
            runs: [
                DecodedRun(length: 6,
                    paragraphStyle: .init(styleType: .heading1, listStyle: nil, isChecklist: false,
                        isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 10, paragraphStyle: nil, isBold: true,
                    isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let encoded = try NoteBodyEncoder.encode(body)
        let decoded = try NoteBodyDecoder.decode(data: encoded)
        XCTAssertEqual(decoded.text, "Title\nBold text\n")
        XCTAssertEqual(decoded.runs.count, 2)
        XCTAssertEqual(decoded.runs[0].paragraphStyle?.styleType, .heading1)
        XCTAssertTrue(decoded.runs[1].isBold)
    }
}
