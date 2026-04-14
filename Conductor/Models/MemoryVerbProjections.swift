import Foundation
import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
enum AppendSlot: String, Codable, Sendable {
    case action
    case outcome
}

@available(iOS 19.0, macOS 26.0, *)
struct ContextProjection: Sendable, Codable {
    let intent: LanguageIntentQuery?
    let activeSubjects: [SubjectStack.Entry]

    private enum CodingKeys: String, CodingKey {
        case intent
        case activeSubjects
    }

    init(intent: LanguageIntentQuery?, activeSubjects: [SubjectStack.Entry]) {
        self.intent = intent
        self.activeSubjects = activeSubjects
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intent, forKey: .intent)
        try container.encode(activeSubjects, forKey: .activeSubjects)
    }
}

struct ActionProjection: Sendable, Codable, Identifiable {
    let id: UUID
    let kind: ActionKind
    let goal: String
    let status: ActionStatus
    let atomCount: Int
}

struct AtomProjection: Sendable, Codable {
    let actionID: UUID?
    let subjectID: UUID?
    let preview: String
    let source: URL?
    let toolName: String?
    let timestamp: Date
}

enum AppendReceipt: Sendable, Codable {
    case accepted(atomID: UUID)
    case refused(reason: String)
}
