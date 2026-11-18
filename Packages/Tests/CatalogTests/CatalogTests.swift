import XCTest
import HubCore

/// Every kit's device.json must decode, with its folder's id unique and unique feature ids,
/// before it can reach Home and the Market. Reads the files from the source tree, so a new kit needs no line here.
final class CatalogTests: XCTestCase {
    func testEveryDeviceJSONDecodesWithUniqueIDs() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources").standardized
        let manifests = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .map { $0.appendingPathComponent("device.json") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        XCTAssertGreaterThanOrEqual(manifests.count, 7)
        var ids = Set<String>()
        for url in manifests {
            let kind = DeviceKind(manifest: url) { UnbuiltDevice(name: "") }
            XCTAssertTrue(ids.insert(kind.id).inserted, "duplicate device id \(kind.id)")
            XCTAssertEqual(Set(kind.features.map(\.id)).count, kind.features.count, "duplicate feature id in \(kind.id)")
        }
    }
}
