import Foundation
import Testing
@testable import Conductor

@Suite("AutomatorActionIndex Tests")
struct AutomatorActionIndexTests {

    @Test("Parses Info.plist dictionary into AutomatorActionInfo")
    func parsesInfoPlist() throws {
        let plist: [String: Any] = [
            "AMName": "Scale Images",
            "AMCategory": "AMCategoryPhotos",
            "AMKeywords": ["resize", "scale", "images", "photos"],
            "AMDescription": ["AMDSummary": "Scales images to a specific size."],
            "AMAccepts": [
                "Types": ["public.image"],
                "Container": "List",
            ],
            "AMProvides": [
                "Types": ["public.image"],
                "Container": "List",
            ],
            "AMDefaultParameters": [
                "scaleFactor": 0.5,
                "scaleType": 0,
            ],
        ]

        let bundleURL = URL(fileURLWithPath: "/System/Library/Automator/Scale Images.action")
        let info = AutomatorActionInfo(bundleURL: bundleURL, plist: plist)

        #expect(info.name == "Scale Images")
        #expect(info.category == "AMCategoryPhotos")
        #expect(info.keywords == ["resize", "scale", "images", "photos"])
        #expect(info.descriptionSummary == "Scales images to a specific size.")
        #expect(info.inputTypes == ["public.image"])
        #expect(info.inputContainer == "List")
        #expect(info.outputTypes == ["public.image"])
        #expect(info.outputContainer == "List")
        #expect(info.defaultParameters["scaleFactor"] == "0.5")
        #expect(info.defaultParameters["scaleType"] == "0")
        #expect(info.bundleURL == bundleURL)
    }

    @Test("Handles missing optional plist keys gracefully")
    func handlesMissingKeys() throws {
        let plist: [String: Any] = [
            "AMName": "Some Action",
        ]
        let bundleURL = URL(fileURLWithPath: "/System/Library/Automator/Some Action.action")
        let info = AutomatorActionInfo(bundleURL: bundleURL, plist: plist)

        #expect(info.name == "Some Action")
        #expect(info.category == "")
        #expect(info.keywords.isEmpty)
        #expect(info.descriptionSummary == "")
        #expect(info.inputTypes.isEmpty)
        #expect(info.outputTypes.isEmpty)
        #expect(info.defaultParameters.isEmpty)
    }
}
