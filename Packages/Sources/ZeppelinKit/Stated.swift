import Foundation

/// The Zeppelin's local API, the one B&W's app uses: JSON queries POSTed to
/// `https://<ip>:42425/mesh/node/<node>/channel/<channel>/message` (self-signed certificate, no login).
/// Some replies come back in the HTTP body, the rest only on the WebSocket `wss://<ip>:42425/messages`,
/// which also pushes every change.
public enum Stated {
    public static let port = 42425
    public static let channel = "com.bowerswilkins.stated.service+provider"

    public enum Property {
        public static let bass = "liberty.property.gain.bass"  // hundredths of a dB, -600...600
        public static let treble = "liberty.property.gain.treble"
        public static let light = "liberty.lights.hardware-downlight"
        public static let nowPlaying = "liberty.oobed.audiotile"
    }

    public enum Command: String {
        case playPause = "liberty.command.play_pause"
        case next = "liberty.command.next_track"
        case previous = "liberty.command.previous_track"
    }

    public static func query(_ name: String, _ parameters: [String: Any] = [:]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["type": "query", "method": ["name": name, "parameters": parameters]])
    }

    public static func get(_ property: String) -> Data { query("get_property", ["property": property]) }
    public static func set(_ property: String, _ value: Any) -> Data { query("set_property", ["property": property, "value": value]) }
    public static func setVolume(_ value: Int, muted: Bool) -> Data {
        query("set_volume", ["value": min(max(value, 0), 100), "source": "", "muted": muted])
    }
    public static func send(_ command: Command) -> Data { query("send_command", ["command": command.rawValue]) }

    public struct Light: Equatable {
        public var enabled: Bool
        public var brightness: Double  // 0.01...1
        public var red, green, blue: Int

        public init(enabled: Bool, brightness: Double, red: Int, green: Int, blue: Int) {
            (self.enabled, self.brightness, self.red, self.green, self.blue) = (enabled, brightness, red, green, blue)
        }

        public var json: [String: Any] {
            ["enabled": enabled, "brightness": brightness, "rgb": ["red": red, "green": green, "blue": blue], "supported": true]
        }
    }

    public struct NowPlaying: Equatable {
        public var title, artist, album, service: String
        public var state: Int
        public var durationMs, elapsedMs: Int
        public var actions: [String]
    }

    public enum Event: Equatable {
        /// A change, pushed as "volume_changed".
        case volume(Int)
        /// The answer to get_volume. set_volume's own "success" reply also looks like this but carries the old
        /// volume (seen on device), so only a get_volume answer should be used.
        case volumeReply(Int)
        case bass(Int)
        case treble(Int)
        case light(Light)
        /// Nil when nothing plays on this speaker.
        case nowPlaying(NowPlaying?)
        case update(available: Bool, version: String)
    }

    /// Events in a WebSocket message. Every speaker in a B&W mesh relays the others' messages, so only `node`'s count.
    public static func events(inPush data: Data, node: String) -> [Event] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let args = (object["payload"] as? [String: Any])?["args"] as? [String: Any],
              args["sendingNodeID"] as? String == node,
              let method = (args["message"] as? [String: Any])?["method"] as? [String: Any],
              let name = method["name"] as? String, let parameters = method["parameters"] as? [String: Any]
        else { return [] }
        return events(name: name, parameters: parameters, node: node)
    }

    /// Events in an HTTP reply body (`get_property` answers there; `get_volume` and the now-playing record don't).
    public static func events(inReply data: Data, node: String) -> [Event] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let available = object["update_available"] as? Bool {
            return [.update(available: available, version: object["update_version"] as? String ?? "")]
        }
        return events(name: "success", parameters: object, node: node)
    }

    static func events(name: String, parameters p: [String: Any], node: String) -> [Event] {
        if let value = p["value"] as? Int, p["muted"] is Bool, p["property"] == nil {
            return name == "volume_changed" ? [.volume(value)] : name == "success" ? [.volumeReply(value)] : []
        }
        guard ["property_changed", "success"].contains(name), let property = p["property"] as? String else { return [] }
        switch property {
        case Property.bass: return (p["value"] as? Int).map { [.bass($0)] } ?? []
        case Property.treble: return (p["value"] as? Int).map { [.treble($0)] } ?? []
        case Property.light:
            guard let v = p["value"] as? [String: Any], let rgb = v["rgb"] as? [String: Any] else { return [] }
            return [.light(Light(enabled: v["enabled"] as? Bool ?? false, brightness: (v["brightness"] as? NSNumber)?.doubleValue ?? 0,
                                 red: rgb["red"] as? Int ?? 0, green: rgb["green"] as? Int ?? 0, blue: rgb["blue"] as? Int ?? 0))]
        case Property.nowPlaying:
            guard let tiles = p["value"] as? [String: [String: Any]] else { return [] }
            // Keyed "<node>+<service>"; a grouped speaker shows up in another node's tile under sinkNodeIDs.
            let tile = tiles.first { $0.key.hasPrefix(node) || ($0.value["sinkNodeIDs"] as? [String])?.contains(node) == true }?.value
            return [.nowPlaying(tile.map {
                NowPlaying(title: $0["title"] as? String ?? "", artist: $0["artist"] as? String ?? "", album: $0["album"] as? String ?? "",
                           service: $0["serviceName"] as? String ?? "", state: $0["state"] as? Int ?? 0,
                           durationMs: $0["duration"] as? Int ?? 0, elapsedMs: $0["elapsedTime"] as? Int ?? 0,
                           actions: $0["enabledPlaybackActions"] as? [String] ?? [])
            })]
        default: return []
        }
    }
}

/// The StreamSDK settings API on plain HTTP port 80 (`/api/getData`, `/api/setData`). Only auto standby is used.
public enum StreamSDK {
    public static let autoStandby = "settings:/system/maxIdleTime"  // seconds, 0 = never
    public static let autoStandbyChoices = [0, 300, 600, 900, 1200, 1800]

    public static func getURL(ip: String, path: String) -> URL {
        var c = URLComponents(string: "http://\(ip)/api/getData")!
        c.queryItems = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "roles", value: "value")]
        return c.url!
    }

    public static func setURL(ip: String, path: String, int value: Int) -> URL {
        var c = URLComponents(string: "http://\(ip)/api/setData")!
        c.queryItems = [URLQueryItem(name: "path", value: path), URLQueryItem(name: "role", value: "value"),
                        URLQueryItem(name: "value", value: #"{"type":"i32_","i32_":\#(value)}"#)]
        return c.url!
    }

    /// `{"type":"i32_","i32_":1200}`, possibly wrapped in a list or under "value".
    public static func int(_ data: Data) -> Int? {
        let object = try? JSONSerialization.jsonObject(with: data)
        let typed = (object as? [[String: Any]])?.first ?? (object as? [String: Any]).map { ($0["value"] as? [String: Any]) ?? $0 }
        return (typed?["i32_"] as? NSNumber)?.intValue
    }
}
