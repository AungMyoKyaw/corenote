import XCTest
@testable import corenote

final class MarkdownToNoteTests: XCTestCase {
    func testPlainText() {
        let result = MarkdownToNote.convert("Hello World")
        XCTAssertEqual(result.text, "Hello World\n")
        XCTAssertEqual(result.runs.count, 1)
    }

    func testHeading() {
        let result = MarkdownToNote.convert("# My Title")
        XCTAssertEqual(result.text, "My Title\n")
        XCTAssertEqual(result.runs[0].paragraphStyle?.styleType, .heading1)
    }

    func testHeading2() {
        let result = MarkdownToNote.convert("## Subtitle")
        XCTAssertEqual(result.text, "Subtitle\n")
        XCTAssertEqual(result.runs[0].paragraphStyle?.styleType, .heading2)
    }

    func testBoldText() {
        let result = MarkdownToNote.convert("Hello **bold** world")
        XCTAssertEqual(result.text, "Hello bold world\n")
        XCTAssertTrue(result.runs.contains { $0.isBold })
    }

    func testStrikethrough() {
        let result = MarkdownToNote.convert("~~removed~~")
        XCTAssertEqual(result.text, "removed\n")
        XCTAssertTrue(result.runs[0].isStrikethrough)
    }

    func testBulletList() {
        let result = MarkdownToNote.convert("- Item 1\n- Item 2")
        XCTAssertEqual(result.text, "Item 1\nItem 2\n")
        XCTAssertEqual(result.runs[0].paragraphStyle?.listStyle, 100)
    }

    func testNumberedList() {
        let result = MarkdownToNote.convert("1. First\n2. Second")
        XCTAssertEqual(result.text, "First\nSecond\n")
        XCTAssertEqual(result.runs[0].paragraphStyle?.listStyle, 200)
    }

    func testChecklist() {
        let result = MarkdownToNote.convert("- [x] Done\n- [ ] Not done")
        XCTAssertEqual(result.text, "Done\nNot done\n")
        XCTAssertTrue(result.runs[0].paragraphStyle?.isChecklist == true)
        XCTAssertTrue(result.runs[0].paragraphStyle?.isChecklistDone == true)
        XCTAssertTrue(result.runs[1].paragraphStyle?.isChecklist == true)
        XCTAssertFalse(result.runs[1].paragraphStyle?.isChecklistDone == true)
    }

    func testBlockquote() {
        let result = MarkdownToNote.convert("> Quoted text")
        XCTAssertEqual(result.text, "Quoted text\n")
        XCTAssertTrue(result.runs[0].paragraphStyle?.isBlockquote == true)
    }

    func testLink() {
        let result = MarkdownToNote.convert("[click](https://example.com)")
        XCTAssertEqual(result.text, "click\n")
        XCTAssertEqual(result.runs[0].link, "https://example.com")
    }
}
