import Foundation

struct ClaimsExtracted: Event {
    let id = UUID()
    let timestamp = Date()
    let claims: [Claim]
    let origin: Origin
}
