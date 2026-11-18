import SwiftUI
import Observation

public enum DeviceStatus: Equatable, Sendable {
    case notSetUp
    case offline(reason: String?)
    case connecting
    case online(summary: String)

    /// The line under the device's name on its Home card. The offline reason is shown in the device's own screen.
    public var cardLine: String {
        switch self {
        case .notSetUp: "Not set up"
        case .offline: "Offline"
        case .connecting: "Connecting…"
        case .online(let summary): summary
        }
    }
}

/// What every device module implements. Its class lives in App/Devices/<Name>/.
@MainActor
public protocol HomeDevice: AnyObject, Observable {
    var status: DeviceStatus { get }
    /// The device's full screen, including first-time setup while the status is .notSetUp.
    func makeScreen() -> AnyView
}

/// The group a device is listed under on Home and in Market, in this order.
public enum DeviceCategory: String, CaseIterable, Codable, Sendable {
    case fitness, music, climate, cleaning, kitchen, other

    public var title: String { rawValue.capitalized }
}

/// One catalog entry: what the Market shows and how to create the device.
public struct DeviceKind: Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let link: Link
    public let category: DeviceCategory
    public let features: [Feature]
    public let makeDevice: @MainActor () -> any HomeDevice

    public init(id: String, name: String, symbol: String, link: Link, category: DeviceCategory = .other, features: [Feature] = [],
                makeDevice: @escaping @MainActor () -> any HomeDevice) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.link = link
        self.category = category
        self.features = features
        self.makeDevice = makeDevice
    }

    /// Reads a kit's device.json. A broken file is a build mistake, so it stops with the reason;
    /// CatalogTests decodes every device.json, so this can't reach the phone.
    public init(manifest url: URL, makeDevice: @escaping @MainActor () -> any HomeDevice) {
        struct Manifest: Decodable {
            let id, name, symbol: String
            let link: Link
            let category: DeviceCategory
            let features: [Feature]
        }
        let m: Manifest
        do { m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)) }
        catch { preconditionFailure("Can't read \(url.lastPathComponent): \(error)") }
        self.init(id: m.id, name: m.name, symbol: m.symbol, link: m.link, category: m.category, features: m.features, makeDevice: makeDevice)
    }

    /// Kinds grouped by category, in the categories' order; empty categories are left out.
    public static func byCategory(_ kinds: [DeviceKind]) -> [(category: DeviceCategory, kinds: [DeviceKind])] {
        DeviceCategory.allCases.compactMap { category in
            let members = kinds.filter { $0.category == category }
            return members.isEmpty ? nil : (category, members)
        }
    }

    public var workingSummary: String {
        "\(features.filter { $0.status == .working }.count)/\(features.count) working"
    }
}

/// Stands in for a device whose module isn't built yet, so the Market lists it and Add works.
@MainActor
@Observable
public final class UnbuiltDevice: HomeDevice {
    public let name: String

    public init(name: String) { self.name = name }

    public var status: DeviceStatus { .notSetUp }

    public func makeScreen() -> AnyView {
        AnyView(ContentUnavailableView(
            "\(name) isn't built yet", systemImage: "hammer",
            description: Text("Its features are listed in Market. Mark the ones you want and send the wishlist to its session.")))
    }
}
