import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
@Generable
struct LanguageIntentQuery: Sendable, Codable {
    @Guide(description: "The verbs describing what the user wants done")
    var verbs: [IntentVerb]

    @Guide(description: "The subjects the user is asking about — short noun phrases")
    var subjects: [String]

    @Guide(description: "The shape of the answer the user expects")
    var answerShape: AnswerShape

    @Guide(description: "How this turn relates to the prior turn, if at all")
    var continuation: Continuation?

    @available(iOS 19.0, macOS 26.0, *)
    @Generable
    enum Continuation: String, Codable, Sendable {
        case refines
        case extends
        case pivots
        case recalls
    }
}
