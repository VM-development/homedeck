import Foundation
@testable import HubCore

func makeKind(id: String = "test", _ features: [Feature]) throws -> DeviceKind {
    DeviceKind(id: id, name: "Test Device", symbol: "questionmark", link: .bluetooth, features: features) { UnbuiltDevice(name: "Test Device") }
}
