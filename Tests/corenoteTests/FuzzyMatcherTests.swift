import XCTest
@testable import corenote

final class FuzzyMatcherTests: XCTestCase {
    let titles = ["Shopping List", "Meeting Notes", "API Design Doc", "Travel Plans", "Shopping Budget"]

    func testExactMatch() {
        let results = FuzzyMatcher.match(query: "Shopping List", candidates: titles)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "Shopping List")
    }

    func testExactMatchCaseInsensitive() {
        let results = FuzzyMatcher.match(query: "shopping list", candidates: titles)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "Shopping List")
    }

    func testPrefixMatch() {
        let results = FuzzyMatcher.match(query: "Shop", candidates: titles)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains("Shopping List"))
        XCTAssertTrue(results.contains("Shopping Budget"))
    }

    func testContainsMatch() {
        let results = FuzzyMatcher.match(query: "Design", candidates: titles)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], "API Design Doc")
    }

    func testFuzzyMatch() {
        let results = FuzzyMatcher.match(query: "Shoping List", candidates: titles)
        XCTAssertTrue(results.contains("Shopping List"))
    }

    func testNoMatch() {
        let results = FuzzyMatcher.match(query: "Nonexistent", candidates: titles)
        XCTAssertTrue(results.isEmpty)
    }

    func testShortQuerySkipsFuzzy() {
        let results = FuzzyMatcher.match(query: "Sh", candidates: titles)
        XCTAssertEqual(results.count, 2) // prefix matches only
    }

    func testLevenshteinDistance() {
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("kitten", "sitting"), 3)
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("", "abc"), 3)
        XCTAssertEqual(FuzzyMatcher.levenshteinDistance("abc", "abc"), 0)
    }
}
