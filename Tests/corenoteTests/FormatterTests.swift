import XCTest
@testable import corenote

final class FormatterTests: XCTestCase {
    func testRelativeDate() {
        let now = Date()
        XCTAssertEqual(OutputFormatter.relativeDate(now), "just now")
        let fiveMinAgo = now.addingTimeInterval(-300)
        XCTAssertEqual(OutputFormatter.relativeDate(fiveMinAgo), "5 minutes ago")
        let twoHoursAgo = now.addingTimeInterval(-7200)
        XCTAssertEqual(OutputFormatter.relativeDate(twoHoursAgo), "2 hours ago")
        let yesterday = now.addingTimeInterval(-86400)
        XCTAssertEqual(OutputFormatter.relativeDate(yesterday), "Yesterday")
    }

    func testColorDisabledReturnsPlainText() {
        let result = OutputFormatter.colored("hello", .cyan, forceColor: false)
        XCTAssertEqual(result, "hello")
    }

    func testColorEnabledReturnsANSI() {
        let result = OutputFormatter.colored("hello", .cyan, forceColor: true)
        XCTAssertTrue(result.contains("\u{1B}["))
        XCTAssertTrue(result.contains("hello"))
    }

    func testPadRight() {
        XCTAssertEqual(OutputFormatter.padRight("hi", width: 5), "hi   ")
        XCTAssertEqual(OutputFormatter.padRight("hello", width: 3), "hello")
    }
}
