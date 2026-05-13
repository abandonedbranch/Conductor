import Foundation
@testable import Conductor

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var scripted: [URL: Data] = [:]
    var requested: [URL] = []
    func get(_ url: URL) async throws -> Data {
        requested.append(url)
        guard let d = scripted[url] else { throw URLError(.badURL) }
        return d
    }
}
