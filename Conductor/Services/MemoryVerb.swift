import FoundationModels

@available(iOS 19.0, macOS 26.0, *)
protocol MemoryVerb: Tool, AffordanceBearing {
    /// Stable identifier used in `assignedVerbNames`.
    var verbName: String { get }
}
