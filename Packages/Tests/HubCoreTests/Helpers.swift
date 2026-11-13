import Foundation
@testable import HubCore

/// Writes features to a temporary features.json, the way a device package ships them.
func featuresFile(_ features: [Feature]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    try JSONEncoder().encode(features).write(to: url)
    return url
}

func makeKind(id: String = "test", _ features: [Feature]) throws -> DeviceKind {
    DeviceKind(id: id, name: "Test Device", symbol: "questionmark", link: .bluetooth,
               featuresURL: try featuresFile(features)) { UnbuiltDevice(name: "Test Device") }
}
