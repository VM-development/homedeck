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
public enum DeviceCategory: String, CaseIterable, Sendable {
    case fitness = "Fitness"
    case music = "Music"
    case climate = "Climate"
    case cleaning = "Cleaning"
    case kitchen = "Kitchen"
    case other = "Other"
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

    public init(id: String, name: String, symbol: String, link: Link, category: DeviceCategory = .other, featuresURL: URL,
                makeDevice: @escaping @MainActor () -> any HomeDevice) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.link = link
        self.category = category
        self.features = Feature.load(from: featuresURL)
        self.makeDevice = makeDevice
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
