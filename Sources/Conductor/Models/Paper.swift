import Foundation

struct Paper: Sendable, Hashable {
    let title: String
    let abstract: String
    let identifier: String
    let url: URL?
}
