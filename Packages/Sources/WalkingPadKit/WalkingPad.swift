import Foundation

/// KingSmith's "WiLink" protocol on Bluetooth service FE00, as spoken by the WalkingPad C2.
/// The phone writes commands to FE02 (write without response); the pad answers on FE01 notifications.
/// Frames and their evidence: docs/devices/walkingpad-c2/protocol.md.
public enum WalkingPad {
    public static let service = "FE00"
    public static let notifyCharacteristic = "FE01"
    public static let writeCharacteristic = "FE02"
    public static let speedRange = 0.5...6.0

    public enum Mode: UInt8, CaseIterable, Sendable {
        case automatic = 0, manual = 1, standby = 2
    }

    // MARK: Commands

    public static let askStatus = frame(0xA2, [0, 0])
    public static let start = frame(0xA2, [4, 1])
    /// Stop is "speed 0".
    public static let stop = frame(0xA2, [1, 0])

    /// Speed in km/h, sent in 0.1 km/h steps.
    public static func setSpeed(_ kmh: Double) -> Data {
        frame(0xA2, [1, UInt8((kmh.clamped(to: speedRange) * 10).rounded())])
    }

    public static func setMode(_ mode: Mode) -> Data { frame(0xA2, [2, mode.rawValue]) }

    /// F7, group, payload, checksum (sum of group and payload, mod 256), FD.
    static func frame(_ group: UInt8, _ payload: [UInt8]) -> Data {
        let body = [group] + payload
        return Data([0xF7] + body + [checksum(body), 0xFD])
    }

    static func checksum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        UInt8(bytes.reduce(0) { $0 + Int($1) } & 0xFF)
    }

    // MARK: Replies

    public struct Status: Equatable, Sendable {
        /// 0 stopped, 1 running, 4 standby, 7/8/9 start countdown.
        public let beltState: UInt8
        public let speed: Double
        /// Raw mode byte; see `Mode`.
        public let mode: UInt8
        public let seconds: Int
        public let meters: Int
        public let steps: Int

        public var isRunning: Bool { beltState == 1 }
        public var isCountingDown: Bool { (7...9).contains(beltState) }
    }

    public enum Reply: Equatable, Sendable {
        case status(Status)
        /// A well-formed frame of a type we don't decode (settings, stored walk).
        case other(type: UInt8)
    }

    /// Nil for anything that isn't a 20-byte F8 frame with a correct checksum.
    public static func decode(_ data: Data) -> Reply? {
        let b = [UInt8](data)
        guard b.count == 20, b[0] == 0xF8, b[19] == 0xFD, b[18] == checksum(b[1...17]) else { return nil }
        func int(_ at: Int) -> Int { Int(b[at]) << 16 | Int(b[at + 1]) << 8 | Int(b[at + 2]) }
        switch b[1] {
        case 0xA2:
            return .status(Status(beltState: b[2], speed: Double(b[3]) / 10, mode: b[4],
                                  seconds: int(5), meters: int(8) * 10, steps: int(11)))
        default:
            return .other(type: b[1])
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}

public extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
