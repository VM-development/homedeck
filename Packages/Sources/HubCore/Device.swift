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
    func connect() async
    func disconnect() async
    /// The device's full screen, including first-time setup while the status is .notSetUp.
    func makeScreen() -> AnyView
}

/// One catalog entry: what the Market shows and how to create the device.
public struct DeviceKind: Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let link: Link
    public let features: [Feature]
    public let makeDevice: @MainActor () -> any HomeDevice

    public init(id: String, name: String, symbol: String, link: Link, featuresURL: URL,
                makeDevice: @escaping @MainActor () -> any HomeDevice) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.link = link
        self.features = Feature.load(from: featuresURL)
        self.makeDevice = makeDevice
    }

    public var workingSummary: String {
        "\(features.filter { $0.status == .working }.count) of \(features.count) features working"
    }
}

/// Stands in for a device whose module isn't built yet, so the Market lists it and Add works.
@MainActor
@Observable
public final class UnbuiltDevice: HomeDevice {
    public let name: String

    public init(name: String) { self.name = name }

    public var status: DeviceStatus { .notSetUp }
    public func connect() async {}
    public func disconnect() async {}

    public func makeScreen() -> AnyView {
        AnyView(ContentUnavailableView(
            "\(name) isn't built yet", systemImage: "hammer",
            description: Text("Its features are listed in Market. Mark the ones you want and send the wishlist to its session.")))
    }
}
