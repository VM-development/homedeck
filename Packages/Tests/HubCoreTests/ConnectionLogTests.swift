import XCTest
@testable import HubCore

@MainActor
final class ConnectionLogTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    }

    func testEntriesAreTaggedAndSurviveRelaunch() {
        let url = tempURL()
        let log = ConnectionLog(url: url)
        log.tagged("rex5").add("Connected")
        log.add("Fan on", device: "fan")
        let reloaded = ConnectionLog(url: url)
        XCTAssertEqual(reloaded.entries.map(\.device), ["rex5", "fan"])
        XCTAssertEqual(reloaded.entries(for: "fan").map(\.text), ["Fan on"])
        XCTAssertEqual(reloaded.entries(for: nil).count, 2)
    }

    func testKeepsOnlyTheNewestEntries() {
        let url = tempURL()
        let log = ConnectionLog(url: url)
        for i in 0..<(ConnectionLog.limit + 5) { log.add("line \(i)", device: "rex5") }
        XCTAssertEqual(log.entries.count, ConnectionLog.limit)
        XCTAssertEqual(log.entries.first?.text, "line 5")
        XCTAssertEqual(ConnectionLog(url: url).entries.count, ConnectionLog.limit)
    }

    func testShareTextIsNewestFirstWithTheDevice() {
        let log = ConnectionLog(url: tempURL())
        log.add("first", device: "rex5")
        log.add("second", device: "fan")
        let lines = log.shareText(for: nil).split(separator: "\n")
        XCTAssertTrue(lines[0].hasSuffix("[fan] second"))
        XCTAssertTrue(lines[1].hasSuffix("[rex5] first"))
    }
}
