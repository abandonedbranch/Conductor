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

        let queryLower = query.lowercased()
        var results = actions

        if !queryLower.isEmpty {
            results = results.filter { action in
                action.name.lowercased().contains(queryLower)
                || action.category.lowercased().contains(queryLower)
                || action.descriptionSummary.lowercased().contains(queryLower)
                || action.keywords.contains { $0.lowercased().contains(queryLower) }
            }
        }

        if let inputType {
            results = results.filter { $0.inputTypes.contains(inputType) }
        }

        return Array(results.prefix(maxResults))
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
