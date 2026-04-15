import Foundation

struct SubjectStack: Codable, Sendable {
    static let activeCap = 8
    static let archivedCap = 20

    private(set) var active: [Entry]
    private(set) var archived: [Entry]

    init(active: [Entry] = [], archived: [Entry] = []) {
        self.active = active
        self.archived = archived
    }

    struct Entry: Identifiable, Codable, Sendable, Hashable {
        let id: UUID
        let name: String
        let introducedAt: Date
        let introducedByTurn: Int
        var lastTouchedTurn: Int
        let relatesTo: UUID?

        init(
            id: UUID = UUID(),
            name: String,
            introducedAt: Date = .now,
            introducedByTurn: Int,
            lastTouchedTurn: Int,
            relatesTo: UUID? = nil
        ) {
            self.id = id
            self.name = name
            self.introducedAt = introducedAt
            self.introducedByTurn = introducedByTurn
            self.lastTouchedTurn = lastTouchedTurn
            self.relatesTo = relatesTo
        }
    }

    mutating func push(name: String, turn: Int, relatesTo: UUID?) {
        let entry = Entry(
            name: name,
            introducedByTurn: turn,
            lastTouchedTurn: turn,
            relatesTo: relatesTo
        )
        active.append(entry)
        enforceActiveCap()
    }

    mutating func archiveAll() {
        for entry in active {
            archived.insert(entry, at: 0)
        }
        active.removeAll()
        enforceArchivedCap()
    }

    mutating func touch(id: UUID, turn: Int) {
        if let i = active.firstIndex(where: { $0.id == id }) {
            active[i].lastTouchedTurn = turn
        } else if let i = archived.firstIndex(where: { $0.id == id }) {
            archived[i].lastTouchedTurn = turn
        }
    }

    private mutating func enforceActiveCap() {
        while active.count > Self.activeCap {
            let oldest = active.removeFirst()
            archived.insert(oldest, at: 0)
        }
        enforceArchivedCap()
    }

    private mutating func enforceArchivedCap() {
        guard archived.count > Self.archivedCap else { return }
        // Drop the least-recently-touched entries.
        archived.sort { $0.lastTouchedTurn > $1.lastTouchedTurn }
        archived = Array(archived.prefix(Self.archivedCap))
    }
}
