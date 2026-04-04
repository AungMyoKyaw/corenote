import XCTest
@testable import corenote

final class NoteToMarkdownTests: XCTestCase {
    func testPlainText() {
        let body = DecodedNoteBody(
            text: "Hello World\n",
            runs: [DecodedRun(length: 12, paragraphStyle: nil, isBold: false,
                              isUnderlined: false, isStrikethrough: false,
                              link: nil, attachment: nil)]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertEqual(md, "Hello World")
    }

    func testHeading1() {
        let body = DecodedNoteBody(
            text: "Title\nBody text\n",
            runs: [
                DecodedRun(length: 6, paragraphStyle: .init(
                    styleType: .heading1, listStyle: nil, isChecklist: false,
                    isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 10, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.hasPrefix("# Title\n"))
        XCTAssertTrue(md.contains("Body text"))
    }

    func testBoldText() {
        let body = DecodedNoteBody(
            text: "Hello Bold\n",
            runs: [
                DecodedRun(length: 6, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 5, paragraphStyle: nil, isBold: true,
                    isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("**Bold**"))
    }

    func testStrikethrough() {
        let body = DecodedNoteBody(
            text: "removed\n",
            runs: [
                DecodedRun(length: 8, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: true,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("~~removed~~"))
    }

    func testLink() {
        let body = DecodedNoteBody(
            text: "click here\n",
            runs: [
                DecodedRun(length: 11, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: false,
                    link: "https://example.com", attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("[click here](https://example.com)"))
    }

    func testBulletList() {
        let body = DecodedNoteBody(
            text: "Item 1\nItem 2\n",
            runs: [
                DecodedRun(length: 7, paragraphStyle: .init(
                    styleType: nil, listStyle: 100, isChecklist: false,
                    isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 7, paragraphStyle: .init(
                    styleType: nil, listStyle: 100, isChecklist: false,
                    isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("- Item 1"))
        XCTAssertTrue(md.contains("- Item 2"))
    }

    func testChecklist() {
        let body = DecodedNoteBody(
            text: "Done\nNot done\n",
            runs: [
                DecodedRun(length: 5, paragraphStyle: .init(
                    styleType: nil, listStyle: nil, isChecklist: true,
                    isChecklistDone: true, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
                DecodedRun(length: 9, paragraphStyle: .init(
                    styleType: nil, listStyle: nil, isChecklist: true,
                    isChecklistDone: false, isBlockquote: false, indentAmount: 0),
                    isBold: false, isUnderlined: false, isStrikethrough: false,
                    link: nil, attachment: nil),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("- [x] Done"))
        XCTAssertTrue(md.contains("- [ ] Not done"))
    }

    func testAttachmentPlaceholder() {
        let body = DecodedNoteBody(
            text: "\u{FFFC}\n",
            runs: [
                DecodedRun(length: 2, paragraphStyle: nil, isBold: false,
                    isUnderlined: false, isStrikethrough: false, link: nil,
                    attachment: .init(identifier: "abc-123", typeUTI: "public.jpeg")),
            ]
        )
        let md = NoteToMarkdown.convert(body)
        XCTAssertTrue(md.contains("[Image: abc-123]"))
    }
}
