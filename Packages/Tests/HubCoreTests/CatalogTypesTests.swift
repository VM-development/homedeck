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
        XCTAssertEqual(kind.workingSummary, "1 of 3 features working")
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
}
