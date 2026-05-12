import Foundation

protocol SearchBackend: Sendable {
    static var target: String { get }
    static func search(terms: String, limit: Int, http: any HTTPClient) async throws -> [Paper]
}
