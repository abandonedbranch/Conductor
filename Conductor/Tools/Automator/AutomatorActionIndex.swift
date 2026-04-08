import Foundation

actor AutomatorActionIndex {
    private var actions: [AutomatorActionInfo] = []
    private var isLoaded = false

    init() {}

    /// Test-only initializer with preloaded actions.
    init(preloaded: [AutomatorActionInfo]) {
        actions = preloaded
        isLoaded = true
    }

    func search(query: String, inputType: String?, maxResults: Int) -> [AutomatorActionInfo] {
        if !isLoaded {
            loadIndex()
        }

        var candidates = actions

        if let inputType {
            candidates = candidates.filter { $0.inputTypes.contains(inputType) }
        }

        let queryLower = query.lowercased()

        guard !queryLower.isEmpty else {
            return Array(candidates.prefix(maxResults))
        }

        let terms = queryLower.split(separator: " ").map(String.init)

        var scored: [(action: AutomatorActionInfo, score: Int)] = []
        for action in candidates {
            var score = 0
            let nameLower = action.name.lowercased()
            let descLower = action.descriptionSummary.lowercased()
            let catLower = action.category.lowercased()
            let kwLower = action.keywords.map { $0.lowercased() }

            for term in terms {
                if nameLower.contains(term) { score += 3 }
                if kwLower.contains(where: { $0.contains(term) }) { score += 2 }
                if descLower.contains(term) { score += 1 }
                if catLower.contains(term) { score += 1 }
            }

            if score > 0 {
                scored.append((action, score))
            }
        }

        scored.sort { $0.score > $1.score }
        return scored.prefix(maxResults).map(\.action)
    }

    private func loadIndex() {
        let automatorDir = URL(fileURLWithPath: "/System/Library/Automator")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: automatorDir,
            includingPropertiesForKeys: nil
        ) else {
            isLoaded = true
            return
        }

        for bundleURL in contents where bundleURL.pathExtension == "action" {
            let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }
            actions.append(AutomatorActionInfo(bundleURL: bundleURL, plist: plist))
        }

        isLoaded = true
    }
}
