/// Noise control modes for the Rex5 (model H6), from Noble FoKus Android 1.9.5 (`ANC.R5_ANC_INFO_LIST`).
public enum ANCMode: UInt8, CaseIterable, Sendable {
    case off = 0, on = 1, ambient = 2

    public var title: String {
        switch self {
        case .off: "Off"
        case .on: "ANC"
        case .ambient: "Ambient"
        }
    }

    public var packet: GaiaPacket { GaiaPacket(command: Rex5Command.setANCMode.rawValue, payload: [rawValue]) }
}

/// Qualcomm GAIA v3 Music Processing (feature 5), which the Rex5 reports as supported (2026-11-12).
/// Noble's own EQ command (0x0E01) is refused as "command not supported" on this firmware.
/// Encoding from Qualcomm's GAIA client library inside Noble FoKus Android 1.9.5 (`V3MusicProcessingPlugin`, `BandInfo`).
public enum MusicProcessing {
    public static let off: UInt8 = 0
    public static let custom: UInt8 = 63
    public static let gainRange = -12...12

    public static let getPresets = command(1)
    public static let getSelected = command(2)
    public static let setSelected = command(3)
    public static let getBandCount = command(4)
    public static let getBands = command(5)
    public static let setGains = command(6)

    /// Feature 5 in the v3 command layout: feature (7 bits) | type (2) | id (7).
    static func command(_ id: UInt16) -> UInt16 { 5 << 9 | id }

    public static func packet(_ command: UInt16, _ payload: [UInt8] = []) -> GaiaPacket {
        GaiaPacket(vendor: GaiaPacket.qtilV3, command: command, payload: payload)
    }

    /// Gains in dB for consecutive bands starting at `firstBand`, sent as 1/60 dB signed 16-bit big-endian
    /// after the first and last band numbers.
    public static func gainsPacket(_ gains: [Int], firstBand: Int = 0) -> GaiaPacket {
        let values = gains.flatMap { gain -> [UInt8] in
            let bits = UInt16(bitPattern: Int16(min(max(gain, gainRange.lowerBound), gainRange.upperBound) * 60))
            return [UInt8(bits >> 8), UInt8(bits & 0xFF)]
        }
        return packet(setGains, [UInt8(firstBand), UInt8(firstBand + max(gains.count - 1, 0))] + values)
    }

    /// "Available presets" response: a count, then that many preset numbers.
    public static func presets(from data: [UInt8]) -> [UInt8] {
        guard let count = data.first, data.count > Int(count) else { return [] }
        return Array(data[1...Int(count)])
    }

    public struct Band: Equatable, Sendable {
        public let frequency: Int
        public var gain: Double
    }

    /// "User set configuration" response: first band, last band, then 7 bytes per band:
    /// frequency (u16), Q (u16 / 4096), filter (u8), gain (s16 / 60 dB).
    public static func bands(from data: [UInt8]) -> [Band] {
        guard data.count >= 2, data[1] >= data[0] else { return [] }
        let count = Int(data[1] - data[0]) + 1
        guard data.count >= 2 + count * 7 else { return [] }
        return (0..<count).map { band in
            let b = Array(data[(2 + band * 7)..<(9 + band * 7)])
            return Band(frequency: Int(b[0]) << 8 | Int(b[1]),
                        gain: Double(Int16(bitPattern: UInt16(b[5]) << 8 | UInt16(b[6]))) / 60)
        }
    }

    /// Off, Custom, or the built-in presets numbered in the order the earbuds list them (their own names aren't known).
    public static func title(of preset: UInt8, among presets: [UInt8]) -> String {
        switch preset {
        case off: return "Off"
        case custom: return "Custom"
        default:
            let builtIn = presets.filter { $0 != off && $0 != custom }
            return "Preset \((builtIn.firstIndex(of: preset) ?? Int(preset) - 1) + 1)"
        }
    }
}
