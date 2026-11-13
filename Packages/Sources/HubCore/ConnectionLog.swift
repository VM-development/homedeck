import Foundation
import Observation

/// Append-only JSON-lines log of every device's exchanges, tagged by device id. Keeps the newest 500
/// and trims the file at launch.
@MainActor
@Observable
public final class ConnectionLog {
    public struct Entry: Codable, Equatable, Sendable {
        public let date: Date
        public let device: String
        public let text: String
    }

    public static let limit = 500
    nonisolated public static let defaultURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("connection-log.jsonl")
    public static let shared = ConnectionLog()

    public private(set) var entries: [Entry]
    private let url: URL

    public init(url: URL = ConnectionLog.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n") ?? []
        entries = lines.suffix(Self.limit).compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
        if lines.count > Self.limit {  // trim the file once per launch; it only grows by appends while running
            try? entries.compactMap(Self.line).reduce(Data(), +).write(to: url, options: .atomic)
        }
    }

    public func add(_ text: String, device: String) {
        let entry = Entry(date: Date(), device: device, text: text)
        entries.append(entry)
        if entries.count > Self.limit { entries.removeFirst() }
        if let line = Self.line(entry) { append(line) }
    }

    public func entries(for device: String?) -> [Entry] {
        guard let device else { return entries }
        return entries.filter { $0.device == device }
    }

    /// Newest first, for the Share button.
    public func shareText(for device: String?) -> String {
        let formatter = ISO8601DateFormatter()
        return entries(for: device).reversed()
            .map { "\(formatter.string(from: $0.date)) [\($0.device)] \($0.text)" }
            .joined(separator: "\n")
    }

    public func tagged(_ device: String) -> DeviceLogger { DeviceLogger(device: device, log: self) }

    private func append(_ line: Data) {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? line.write(to: url, options: .atomic)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private static func line(_ entry: Entry) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(entry)).map { $0 + Data("\n".utf8) }
    }
}

/// A device's view of the shared log, so its code keeps calling `log.add("...")`.
@MainActor
public struct DeviceLogger {
    public let device: String
    let log: ConnectionLog

    public func add(_ text: String) { log.add(text, device: device) }
}
