import Foundation
import Testing
@testable import Conductor

@Suite("AutomatorActionIndex Tests", .serialized)
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

    // MARK: - Search

    @Test("Matches actions by name substring")
    func searchByName() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: ["AMName": "Scale Images"]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/b.action"), plist: ["AMName": "Copy Finder Items"]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/c.action"), plist: ["AMName": "Move Finder Items"]),
        ]
        let index = AutomatorActionIndex()
        await index.loadForTesting(actions)
        let results = await index.search(query: "scale", inputType: nil, maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].name == "Scale Images")
    }

    @Test("Matches actions by keyword")
    func searchByKeyword() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: [
                "AMName": "Scale Images",
                "AMKeywords": ["resize", "shrink"],
            ]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/b.action"), plist: ["AMName": "Ask for Text"]),
        ]
        let index = AutomatorActionIndex()
        await index.loadForTesting(actions)
        let results = await index.search(query: "resize", inputType: nil, maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].name == "Scale Images")
    }

    @Test("Filters by input UTI type")
    func searchFiltersByInputType() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: [
                "AMName": "Scale Images",
                "AMAccepts": ["Types": ["public.image"], "Container": "List"],
            ]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/b.action"), plist: [
                "AMName": "Combine PDF Pages",
                "AMAccepts": ["Types": ["com.adobe.pdf"], "Container": "List"],
            ]),
        ]
        let index = AutomatorActionIndex()
        await index.loadForTesting(actions)
        let results = await index.search(query: "", inputType: "public.image", maxResults: 5)
        #expect(results.count == 1)
        #expect(results[0].name == "Scale Images")
    }

    @Test("Respects maxResults limit")
    func searchRespectsLimit() async {
        let actions = (1...10).map { i in
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/\(i).action"), plist: ["AMName": "Action \(i)"])
        }
        let index = AutomatorActionIndex()
        await index.loadForTesting(actions)
        let results = await index.search(query: "action", inputType: nil, maxResults: 3)
        #expect(results.count == 3)
    }

    @Test("Case-insensitive search")
    func searchCaseInsensitive() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: ["AMName": "Scale Images"]),
        ]
        let index = AutomatorActionIndex()
        await index.loadForTesting(actions)
        let results = await index.search(query: "SCALE", inputType: nil, maxResults: 5)
        #expect(results.count == 1)
    }

    @Test("Name matches rank higher than description-only matches")
    func searchRanksNameMatchesHigher() async {
        let actions = [
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/a.action"), plist: [
                "AMName": "Import Files into iPhoto",
                "AMDescription": ["AMDSummary": "Imports images into iPhoto."],
            ]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/b.action"), plist: [
                "AMName": "Scale Images",
            ]),
            AutomatorActionInfo(bundleURL: URL(fileURLWithPath: "/c.action"), plist: [
                "AMName": "Crop Images",
            ]),
        ]
        let index = AutomatorActionIndex()
        await index.loadForTesting(actions)
        let results = await index.search(query: "images", inputType: nil, maxResults: 3)
        #expect(results.count == 3)
        // Description-only match ("Import Files into iPhoto") should be last
        #expect(results[2].name == "Import Files into iPhoto")
    }
}
