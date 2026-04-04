import Foundation

struct Folder: Sendable {
    let pk: Int64
    let uuid: String
    let name: String
    let accountName: String
    let parentPK: Int64?
    let noteCount: Int
}
