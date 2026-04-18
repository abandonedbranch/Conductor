import Foundation

protocol Event: Sendable {
    var id: UUID { get }
    var origin: Origin { get }
    var timestamp: Date { get }
}
