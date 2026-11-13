import Foundation
import Observation

/// Which kinds the owner added to Home, and one live device per kind.
@MainActor
@Observable
public final class DeviceStore {
    static let key = "deviceStore.added"

    public let kinds: [DeviceKind]
    public private(set) var addedIDs: [String]
    @ObservationIgnored private var devices: [String: any HomeDevice] = [:]
    private let defaults: UserDefaults

    public init(kinds: [DeviceKind], defaults: UserDefaults = .standard) {
        self.kinds = kinds
        self.defaults = defaults
        let known = Set(kinds.map(\.id))
        addedIDs = (defaults.stringArray(forKey: Self.key) ?? []).filter(known.contains)
        // Added devices start at launch, so Bluetooth state restoration and background work find them.
        for kind in added { _ = device(for: kind) }
    }

    public var added: [DeviceKind] { addedIDs.compactMap(kind(id:)) }
    public func kind(id: String) -> DeviceKind? { kinds.first { $0.id == id } }
    public func isAdded(_ kind: DeviceKind) -> Bool { addedIDs.contains(kind.id) }

    public func add(_ kind: DeviceKind) {
        guard !isAdded(kind) else { return }
        addedIDs.append(kind.id)
        defaults.set(addedIDs, forKey: Self.key)
    }

    /// Takes the card off Home. It doesn't disconnect: the device may be in use.
    public func remove(_ kind: DeviceKind) {
        addedIDs.removeAll { $0 == kind.id }
        defaults.set(addedIDs, forKey: Self.key)
    }

    /// The same instance every time: device classes hold live connections.
    public func device(for kind: DeviceKind) -> any HomeDevice {
        if let device = devices[kind.id] { return device }
        let device = kind.makeDevice()
        devices[kind.id] = device
        return device
    }
}
