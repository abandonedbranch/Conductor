import Foundation

protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession = .shared
    func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
