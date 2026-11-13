import Foundation

/// Everything the app and widgets show about the earbuds.
public struct EarbudSnapshot: Codable, Equatable, Sendable {
    public enum Link: String, Codable, Sendable {
        case connected, connecting, disconnected, paused, notFound, bluetoothOff
    }

    public var link: Link
    public var leftBattery: Int?
    public var rightBattery: Int?
    public var batteryReadAt: Date?
    public var firmware: String?
    public var devices: [PairedDevice]
    public var thisPhoneName: String?
    public var updatedAt: Date

    public init(link: Link = .disconnected, leftBattery: Int? = nil, rightBattery: Int? = nil,
                batteryReadAt: Date? = nil, firmware: String? = nil, devices: [PairedDevice] = [],
                thisPhoneName: String? = nil, updatedAt: Date = Date()) {
        self.link = link
        self.leftBattery = leftBattery
        self.rightBattery = rightBattery
        self.batteryReadAt = batteryReadAt
        self.firmware = firmware
        self.devices = devices
        self.thisPhoneName = thisPhoneName
        self.updatedAt = updatedAt
    }

    public var isThisPhoneConnected: Bool {
        devices.first { $0.name == thisPhoneName }?.isConnected == true
    }

    public var otherConnectedNames: [String] {
        guard link == .connected else { return [] }
        return devices.filter { $0.isConnected && $0.name != thisPhoneName }.map(\.name)
    }

    /// The link is up and the earbuds list this iPhone as connected.
    public var isConnectedHere: Bool {
        link == .connected && isThisPhoneConnected
    }

    /// Status line for the medium widget and Home.
    public var statusLine: String {
        if isConnectedHere { return "Connected to this iPhone" }
        switch link {
        case .connecting: return "Connecting…"
        case .notFound: return "Earbuds not found"
        case .bluetoothOff: return "Bluetooth unavailable"
        default: return "Not connected"
        }
    }

    /// Single status line for the lock-screen widget.
    public var lockStatusLine: String {
        let other = otherConnectedNames.first
        if isConnectedHere { return other.map { "Connected · also \($0)" } ?? "Connected" }
        if let other { return "Also: \(other)" }
        return "Not connected"
    }

    /// "80%"; "In case" when the earbuds answered "unknown" (0xFF), which an earbud in the case reads
    /// (confirmed 2026-11-11); "—" before any reading.
    // ponytail: an earbud out of range of the other may also read 0xFF; not seen yet.
    public func batteryText(_ percent: Int?, inCase: String = "In case") -> String {
        percent.map { "\($0)%" } ?? (batteryReadAt == nil ? "—" : inCase)
    }

    /// The connected entry whose name contains "iPhone", offered as the default choice for "This iPhone".
    public static func suggestedThisPhone(in devices: [PairedDevice]) -> String? {
        devices.first { $0.isConnected && $0.name.localizedCaseInsensitiveContains("iPhone") }?.name
    }

    /// True when a widget would look different: link state, who is connected, or battery moved 5+ points.
    public func visiblyDiffers(from other: EarbudSnapshot) -> Bool {
        link != other.link
            || isThisPhoneConnected != other.isThisPhoneConnected
            || otherConnectedNames != other.otherConnectedNames
            || Self.batteryMoved(leftBattery, other.leftBattery)
            || Self.batteryMoved(rightBattery, other.rightBattery)
    }

    static func batteryMoved(_ a: Int?, _ b: Int?) -> Bool {
        guard let a, let b else { return (a == nil) != (b == nil) }
        return abs(a - b) >= 5
    }
}

/// Decides when the widgets need reloading: when the snapshot looks different from what they last loaded,
/// not from the previous snapshot, so small battery steps can't add up unseen.
public struct WidgetReloadGate: Sendable {
    public private(set) var shown: EarbudSnapshot

    public init(shown: EarbudSnapshot) { self.shown = shown }

    public mutating func shouldReload(for next: EarbudSnapshot) -> Bool {
        guard next.visiblyDiffers(from: shown) else { return false }
        shown = next
        return true
    }
}

/// Reads and writes the snapshot JSON shared through the App Group.
public enum SnapshotFile {
    public static let appGroup = "group.local.homedeck.app"

    public static var defaultURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("snapshot.json")
    }

    public static func write(_ snapshot: EarbudSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> EarbudSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(EarbudSnapshot.self, from: data)
    }
}

/// URLs the widgets open; the app performs the matching action.
public enum DeepLink: String, CaseIterable, Sendable {
    case connect, disconnect, tools, devices

    public var url: URL { URL(string: "rex5://\(rawValue)")! }

    public init?(url: URL) {
        guard url.scheme == "rex5", let host = url.host, let link = DeepLink(rawValue: host) else { return nil }
        self = link
    }
}
