import XCTest
@testable import HubCore

@MainActor
final class CatalogTypesTests: XCTestCase {
    func testFeatureListDecodesAllStatuses() throws {
        let json = #"[{"id":"a","title":"A","status":"working"},{"id":"b","title":"B","status":"planned"}]"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data(json.utf8).write(to: url)
        XCTAssertEqual(Feature.load(from: url).map(\.status), [.working, .planned])
    }

    func testWorkingSummaryCountsWorkingFeatures() throws {
        let kind = try makeKind([
            Feature(id: "a", title: "A", status: .working),
            Feature(id: "b", title: "B", status: .planned),
            Feature(id: "c", title: "C", status: .planned),
        ])
        XCTAssertEqual(kind.workingSummary, "1/3 working")
    }

    func testCardLineHidesTheOfflineReason() {
        XCTAssertEqual(DeviceStatus.offline(reason: "Earbuds not found").cardLine, "Offline")
        XCTAssertEqual(DeviceStatus.online(summary: "L 80% · R 75%").cardLine, "L 80% · R 75%")
        XCTAssertEqual(DeviceStatus.notSetUp.cardLine, "Not set up")
        XCTAssertEqual(DeviceStatus.connecting.cardLine, "Connecting…")
    }

    func testUnbuiltDeviceStaysNotSetUp() {
        let device = UnbuiltDevice(name: "Fan")
        XCTAssertEqual(device.status, .notSetUp)
    }

    func testKindsGroupByCategoryInOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("[]".utf8).write(to: url)
        func kind(_ id: String, _ category: DeviceCategory) -> DeviceKind {
            DeviceKind(id: id, name: id, symbol: "questionmark", link: .wifi, category: category, featuresURL: url) { UnbuiltDevice(name: id) }
        }
        let groups = DeviceKind.byCategory([kind("fan", .climate), kind("pad", .fitness), kind("air", .climate)])
        XCTAssertEqual(groups.map(\.category), [.fitness, .climate])
        XCTAssertEqual(groups[1].kinds.map(\.id), ["fan", "air"])
    }
}
