import Foundation

struct Step: Sendable, Identifiable, Hashable {
    let id: UUID
    let index: Int
    let verb: Verb

    init(index: Int, verb: Verb) {
        self.id = UUID()
        self.index = index
        self.verb = verb
    }
}
