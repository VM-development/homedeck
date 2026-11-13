import XCTest
@testable import Rex5Kit

final class SnapshotTests: XCTestCase {
    let iPhone = Fixtures.device(Fixtures.iPhoneName, index: 0, connected: true)
    let android = Fixtures.device(Fixtures.androidName, index: 1, connected: true)
    let mac = Fixtures.device("Laptop", index: 2, connected: false)

    func testThisPhoneAndOthers() {
        let snapshot = EarbudSnapshot(link: .connected, devices: [iPhone, android, mac], thisPhoneName: Fixtures.iPhoneName)
        XCTAssertTrue(snapshot.isThisPhoneConnected)
        XCTAssertEqual(snapshot.otherConnectedNames, [Fixtures.androidName])
    }

    func testNoChoiceMeansNotConnected() {
        let snapshot = EarbudSnapshot(link: .connected, devices: [iPhone, android])
        XCTAssertFalse(snapshot.isThisPhoneConnected)
        XCTAssertEqual(snapshot.otherConnectedNames, [Fixtures.iPhoneName, Fixtures.androidName])
    }

    func testStatusLines() {
        var snapshot = EarbudSnapshot(link: .connected, devices: [iPhone, mac], thisPhoneName: Fixtures.iPhoneName)
        XCTAssertTrue(snapshot.isConnectedHere)
        XCTAssertEqual(snapshot.statusLine, "Connected to this iPhone")
        XCTAssertEqual(snapshot.lockStatusLine, "Connected")

        snapshot.devices = [iPhone, android]
        XCTAssertEqual(snapshot.lockStatusLine, "Connected · also \(Fixtures.androidName)")

        snapshot.devices = [Fixtures.device(Fixtures.iPhoneName, index: 0, connected: false), android]
        XCTAssertEqual(snapshot.lockStatusLine, "Also: \(Fixtures.androidName)")

        snapshot.devices = [iPhone, android]
        for link in [EarbudSnapshot.Link.connecting, .paused] {
            snapshot.link = link
            XCTAssertEqual(snapshot.otherConnectedNames, [])
        }

        snapshot.link = .bluetoothOff
        XCTAssertEqual(snapshot.statusLine, "Bluetooth unavailable")

        snapshot.link = .paused
        XCTAssertFalse(snapshot.isConnectedHere)
        XCTAssertEqual(snapshot.statusLine, "Not connected")

        snapshot.link = .notFound
        XCTAssertEqual(snapshot.statusLine, "Earbuds not found")

        snapshot.link = .connecting
        snapshot.devices = [iPhone]
        XCTAssertEqual(snapshot.statusLine, "Connecting…")
        XCTAssertEqual(snapshot.lockStatusLine, "Not connected")
    }

    func testBatteryText() {
        XCTAssertEqual(EarbudSnapshot().batteryText(80), "80%")
        XCTAssertEqual(EarbudSnapshot().batteryText(nil), "—")  // never read
        XCTAssertEqual(EarbudSnapshot(batteryReadAt: .now).batteryText(nil), "In case")  // read as 0xFF
    }

    func testSuggestsConnectedIPhone() {
        XCTAssertEqual(EarbudSnapshot.suggestedThisPhone(in: [android, iPhone]), Fixtures.iPhoneName)
        XCTAssertNil(EarbudSnapshot.suggestedThisPhone(in: [android, mac]))
    }

    func testVisibleDifferences() {
        let base = EarbudSnapshot(link: .connected, leftBattery: 80, rightBattery: 80, devices: [iPhone], thisPhoneName: Fixtures.iPhoneName)
        var smallBatteryChange = base
        smallBatteryChange.leftBattery = 77
        XCTAssertFalse(smallBatteryChange.visiblyDiffers(from: base))

        var bigBatteryChange = base
        bigBatteryChange.rightBattery = 75
        XCTAssertTrue(bigBatteryChange.visiblyDiffers(from: base))

        var unknownBattery = base
        unknownBattery.leftBattery = nil
        XCTAssertTrue(unknownBattery.visiblyDiffers(from: base))

        var takeover = base
        takeover.devices = [iPhone, android]
        XCTAssertTrue(takeover.visiblyDiffers(from: base))

        var dropped = base
        dropped.link = .paused
        XCTAssertTrue(dropped.visiblyDiffers(from: base))
    }

    func testFileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = EarbudSnapshot(link: .connected, leftBattery: 100, rightBattery: nil,
                                      batteryReadAt: Date(timeIntervalSince1970: 1_794_391_200), firmware: "R1330A_20250709_V0.3.2",
                                      devices: [iPhone, android], thisPhoneName: Fixtures.iPhoneName,
                                      updatedAt: Date(timeIntervalSince1970: 1_794_391_260))
        try SnapshotFile.write(snapshot, to: url)
        XCTAssertEqual(SnapshotFile.read(from: url), snapshot)
    }

    func testMissingFileReadsNil() {
        XCTAssertNil(SnapshotFile.read(from: URL(fileURLWithPath: "/nonexistent/snapshot.json")))
    }

    func testDeepLinks() {
        XCTAssertEqual(DeepLink.disconnect.url.absoluteString, "rex5://disconnect")
        XCTAssertEqual(DeepLink(url: URL(string: "rex5://tools")!), .tools)
        XCTAssertNil(DeepLink(url: URL(string: "rex5://nope")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://connect")!))
        DeepLink.allCases.forEach { XCTAssertEqual(DeepLink(url: $0.url), $0) }
    }

    func testWidgetGateMeasuresFromWhatTheWidgetShows() {
        var gate = WidgetReloadGate(shown: EarbudSnapshot(link: .connected, leftBattery: 80))
        // One point at a time never moves 5 from the previous reading, but it does from what the widget shows.
        let reloads = (75...79).reversed().map { gate.shouldReload(for: EarbudSnapshot(link: .connected, leftBattery: $0)) }
        XCTAssertEqual(reloads, [false, false, false, false, true])
        XCTAssertEqual(gate.shown.leftBattery, 75)
    }

    func testWidgetGateReloadsAStaleSavedLink() {
        // The saved file says connected; after a relaunch the app knows nothing yet.
        var gate = WidgetReloadGate(shown: EarbudSnapshot(link: .connected))
        XCTAssertTrue(gate.shouldReload(for: EarbudSnapshot(link: .disconnected)))
        XCTAssertFalse(gate.shouldReload(for: EarbudSnapshot(link: .disconnected)))
    }
}
