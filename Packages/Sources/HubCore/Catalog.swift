import Foundation

public enum Link: String, Codable, Sendable { case bluetooth, wifi }

/// One thing a device's vendor app can do. The list lives in the device package's features.json.
public struct Feature: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case working, planned, notPlanned }

    public let id: String
    public let title: String
    public let status: Status

    public init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }

    /// Reads a features.json. A broken file is a build mistake, so it stops with the reason;
    /// CatalogTests decodes every device's file, so this can't reach the phone.
    public static func load(from url: URL) -> [Feature] {
        do { return try JSONDecoder().decode([Feature].self, from: Data(contentsOf: url)) }
        catch { preconditionFailure("Can't read \(url.lastPathComponent): \(error)") }
    }
}
