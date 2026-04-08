import Foundation

struct AutomatorActionInfo: Sendable {
    let bundleURL: URL
    let name: String
    let category: String
    let keywords: [String]
    let descriptionSummary: String
    let inputTypes: [String]
    let inputContainer: String
    let outputTypes: [String]
    let outputContainer: String
    let defaultParameters: [String: String]

    init(bundleURL: URL, plist: [String: Any]) {
        self.bundleURL = bundleURL
        name = plist["AMName"] as? String ?? ""
        category = plist["AMCategory"] as? String ?? ""
        keywords = plist["AMKeywords"] as? [String] ?? []

        let descDict = plist["AMDescription"] as? [String: Any]
        descriptionSummary = descDict?["AMDSummary"] as? String ?? ""

        let accepts = plist["AMAccepts"] as? [String: Any]
        inputTypes = accepts?["Types"] as? [String] ?? []
        inputContainer = accepts?["Container"] as? String ?? ""

        let provides = plist["AMProvides"] as? [String: Any]
        outputTypes = provides?["Types"] as? [String] ?? []
        outputContainer = provides?["Container"] as? String ?? ""

        let params = plist["AMDefaultParameters"] as? [String: Any] ?? [:]
        var stringParams: [String: String] = [:]
        for (key, value) in params {
            if let intValue = value as? Int {
                stringParams[key] = "\(intValue)"
            } else if let doubleValue = value as? Double, doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
                stringParams[key] = "\(Int(doubleValue))"
            } else {
                stringParams[key] = "\(value)"
            }
        }
        defaultParameters = stringParams
    }
}
