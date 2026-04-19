import Foundation

struct ReadCompleted: Event {
    let id = UUID()
    let timestamp = Date()
    let body: String
    let title: String
    let url: URL
    let origin: Origin
}
