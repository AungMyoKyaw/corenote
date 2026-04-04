import Foundation

struct Note: Sendable {
    let pk: Int64
    let uuid: String
    let title: String
    let snippet: String
    let folderName: String
    let accountName: String
    let createdAt: Date
    let modifiedAt: Date
    let isTrashed: Bool
    let isPasswordProtected: Bool
    let bodyData: Data?

    static let macEpochOffset: TimeInterval = 978307200

    static func dateFromMac(_ macTime: Double) -> Date {
        Date(timeIntervalSince1970: macTime + macEpochOffset)
    }

    static func macFromDate(_ date: Date) -> Double {
        date.timeIntervalSince1970 - macEpochOffset
    }
}
