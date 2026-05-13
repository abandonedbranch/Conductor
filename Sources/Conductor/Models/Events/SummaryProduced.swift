import Foundation

struct SummaryProduced: Event {
    let id = UUID()
    let timestamp = Date()
    let summary: String
    let claims: [String]
    let sentiment: String
    let role: String
    let origin: Origin
}
