import Foundation

/// The AC2729's state and commands, in the short key set Air+ uses for it (`pwr`, `mode`, `om`, …).
/// Values are mixed: some keys are strings ("1"), others ints or bools, and the device wants each in its own type.
public enum Purifier {
    public static let modes = ["P", "A", "S", "M"]  // auto, allergen, sleep, manual
    public static let fanSpeeds = ["1", "2", "3", "t"]  // manual speeds; "t" is turbo, "s" shows while sleeping
    public static let humidityTargets = [40, 50, 60, 70]  // 70 is "Max"
    public static let brightness = [0, 25, 50, 75, 100]

    /// The control body, encrypted and POSTed to /sys/dev/control. Empty ids, as the open-source clients send.
    public static func command(_ pairs: [String: Any]) -> Data {
        let desired = ["CommandType": "app", "DeviceId": "", "EnduserId": ""].merging(pairs) { $1 }
        return try! JSONSerialization.data(withJSONObject: ["state": ["desired": desired]])
    }

    public struct State: Equatable {
        public var power = false
        public var mode = "P"
        public var fanSpeed = "1"
        public var humidify = false
        public var humidityTarget = 50
        public var humidity: Int?
        public var temperature: Int?
        public var pm25: Int?
        public var allergenIndex: Int?
        public var brightness = 100
        public var childLock = false
        public var timer = 0
        public var timerLeft: Int?
        public var error = 0
        public var waterLevel: Int?
        /// Hours left: pre-filter clean, HEPA and carbon replace, wick replace.
        public var preFilter: Int?
        public var hepa: Int?
        public var carbon: Int?
        public var wick: Int?

        public init() {}

        /// From the decrypted `{"state":{"reported":{…}}}`; unknown or missing keys keep `previous`.
        public init?(json: Data, previous: State = State()) {
            guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let r = (object["state"] as? [String: Any])?["reported"] as? [String: Any] else { return nil }
            self = previous
            func string(_ k: String) -> String? { r[k].map { "\($0)" } }
            func int(_ k: String) -> Int? { (r[k] as? NSNumber)?.intValue ?? (r[k] as? String).flatMap { Int($0) } }
            if let v = string("pwr") { power = v == "1" }
            if let v = string("mode") { mode = v }
            if let v = string("om") { fanSpeed = v }
            if let v = string("func") { humidify = v == "PH" }
            if let v = int("rhset") { humidityTarget = v }
            humidity = int("rh") ?? humidity
            temperature = int("temp") ?? temperature
            pm25 = int("pm25") ?? pm25
            allergenIndex = int("iaql") ?? allergenIndex
            if let v = int("aqil") { brightness = v }
            if let v = r["cl"] as? Bool { childLock = v }
            if let v = int("dt") { timer = v }
            timerLeft = int("dtrs") ?? timerLeft
            if let v = int("err") { error = v }
            waterLevel = int("wl") ?? waterLevel
            preFilter = int("fltsts0") ?? preFilter
            hepa = int("fltsts1") ?? hepa
            carbon = int("fltsts2") ?? carbon
            wick = int("wicksts") ?? wick
        }

        /// Error bit 0x8000 is set while the tank is out or empty (seen on device); `wl` stayed at 100 meanwhile.
        public var needsWater: Bool { error & 0x8000 != 0 || waterLevel == 0 }
    }
}
