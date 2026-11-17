import Foundation

/// The Smart Standing Fan 2 Pro (`dmaker.fan.p33`): MIoT properties, each addressed by service and property id.
public enum Fan {
    public enum Property: String, CaseIterable {
        case power, level, mode, swing, angle, speed, timer, light, sound, fault, lock

        var ids: (siid: Int, piid: Int) {
            switch self {
            case .power: (2, 1)
            case .level: (2, 2)  // gear 1-4
            case .mode: (2, 3)  // 0 direct, 1 natural breeze
            case .swing: (2, 4)
            case .angle: (2, 5)  // 30, 60, 90, 120, 140
            case .speed: (2, 6)  // 1-100; read-only in the spec, but open source writes it
            case .timer: (3, 1)  // minutes left, 0 = off
            case .light: (4, 1)
            case .sound: (5, 1)
            case .fault: (6, 2)
            case .lock: (7, 1)
            }
        }
    }

    public static let levels = [1, 2, 3, 4]
    public static let angles = [30, 60, 90, 120, 140]

    public struct State: Equatable {
        public var power = false
        public var level = 1
        public var natural = false
        public var swing = false
        public var angle = 30
        public var speed = 1
        public var timer = 0
        public var light = true
        public var sound = true
        public var lock = false
        public var fault = 0

        public init() {}
    }

    /// One request for every property; the label in "did" comes back with each value.
    public static func read(id: Int) -> Data {
        json(id, "get_properties", Property.allCases.map { ["did": $0.rawValue, "siid": $0.ids.siid, "piid": $0.ids.piid] })
    }

    /// `value` is a Bool or an Int, as the property expects.
    public static func write(_ property: Property, _ value: Any, id: Int) -> Data {
        json(id, "set_properties", [["did": property.rawValue, "siid": property.ids.siid, "piid": property.ids.piid, "value": value]])
    }

    private static func json(_ id: Int, _ method: String, _ params: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
    }

    public struct Reply {
        public let id: Int
        /// Per property: code 0 means done; the value comes with reads.
        public let results: [Property: (code: Int, value: NSNumber?)]
        /// The device's own error for the whole request, such as "-9999 user ack timeout".
        public let error: String?

        public init?(_ json: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let id = object["id"] as? Int else { return nil }
            self.id = id
            error = (object["error"] as? [String: Any]).map { "\($0["code"] ?? "?") \($0["message"] ?? "")" }
            var results: [Property: (code: Int, value: NSNumber?)] = [:]
            for entry in object["result"] as? [[String: Any]] ?? [] {
                guard let label = entry["did"] as? String, let property = Property(rawValue: label) else { continue }
                results[property] = ((entry["code"] as? Int) ?? 0, entry["value"] as? NSNumber)
            }
            self.results = results
        }

        /// The fan's state, with properties missing from the reply left at `previous`.
        public func state(updating previous: State = State()) -> State {
            var s = previous
            func value(_ p: Property) -> NSNumber? { results[p].flatMap { $0.code == 0 ? $0.value : nil } }
            if let v = value(.power) { s.power = v.boolValue }
            if let v = value(.level) { s.level = v.intValue }
            if let v = value(.mode) { s.natural = v.intValue == 1 }
            if let v = value(.swing) { s.swing = v.boolValue }
            if let v = value(.angle) { s.angle = v.intValue }
            if let v = value(.speed) { s.speed = v.intValue }
            if let v = value(.timer) { s.timer = v.intValue }
            if let v = value(.light) { s.light = v.boolValue }
            if let v = value(.sound) { s.sound = v.boolValue }
            if let v = value(.lock) { s.lock = v.boolValue }
            if let v = value(.fault) { s.fault = v.intValue }
            return s
        }
    }
}
