import Foundation

public enum Link: String, Codable, Sendable { case bluetooth, wifi }

/// One thing a device's vendor app can do. The list lives in the device's device.json.
public struct Feature: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case working, planned }

    public let id: String
    public let title: String
    public let status: Status

    public init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }
}
