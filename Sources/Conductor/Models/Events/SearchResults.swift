import Foundation

struct SearchResults: Event {
    let id = UUID()
    let timestamp = Date()
    let papers: [Paper]
    let target: String
    let origin: Origin
}
