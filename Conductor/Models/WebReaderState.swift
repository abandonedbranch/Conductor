import Foundation

struct WebReaderResult: Codable, Hashable {
    let url: URL
    let title: String
    let text: String
}

enum WebReaderStatus: Codable, Hashable {
    case loading(URL)
    case success(WebReaderResult)
    case error(String)
}
