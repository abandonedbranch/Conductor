import Foundation

struct WebReaderResult: Codable, Hashable {
    let url: URL
    let title: String
    let text: String
}
