import XCTest
@testable import HubCore

@MainActor
final class DeviceStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    func testAddedDevicesSurviveRelaunchAndUnknownKindsAreDropped() throws {
        let defaults = freshDefaults()
        defaults.set(["removed-from-registry"], forKey: DeviceStore.key)
        let kind = try makeKind(id: "fan", [])
        let store = DeviceStore(kinds: [kind], defaults: defaults)
        XCTAssertTrue(store.added.isEmpty)
        store.add(kind)
        store.add(kind)
        XCTAssertEqual(DeviceStore(kinds: [kind], defaults: defaults).added.map(\.id), ["fan"])
    }

    func testAddedDeviceIsCreatedOnceAtLaunch() throws {
        var made = 0
        let kind = DeviceKind(id: "fan", name: "Fan", symbol: "fan.floor", link: .wifi,
                              featuresURL: try featuresFile([])) {
            made += 1
            return UnbuiltDevice(name: "Fan")
        }
        let defaults = freshDefaults()
        defaults.set(["fan"], forKey: DeviceStore.key)
        let store = DeviceStore(kinds: [kind], defaults: defaults)
        XCTAssertEqual(made, 1)  // created at launch, so Bluetooth state restoration finds its manager
        XCTAssertTrue(store.device(for: kind) === store.device(for: kind))
        XCTAssertEqual(made, 1)
    }

    func testRemoveTakesTheDeviceOffHome() throws {
        let defaults = freshDefaults()
        let kind = try makeKind(id: "fan", [])
        let store = DeviceStore(kinds: [kind], defaults: defaults)
        store.add(kind)
        store.remove(kind)
        XCTAssertFalse(store.isAdded(kind))
        XCTAssertTrue(DeviceStore(kinds: [kind], defaults: defaults).added.isEmpty)
    }
}
