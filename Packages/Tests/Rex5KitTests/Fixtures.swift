@testable import Rex5Kit

/// Device-list packets in the format captured from a Rex5 on 2026-11-11, with made-up device names and address bytes.
enum Fixtures {
    static func packet(_ hex: String) -> GaiaPacket {
        let bytes = hex.split(separator: " ").map { UInt8($0, radix: 16)! }
        return GaiaPacket(bytes: bytes)!
    }

    static let androidConnected = packet("00 0A 03 2C 00 00 54 C3 A9 6C C3 A9 70 68 6F 6E 65 00 00 00 00 00 00 00 00 00 00 11 22 33 01")
    static let androidDisconnected = packet("00 0A 03 2C 00 00 54 C3 A9 6C C3 A9 70 68 6F 6E 65 00 00 00 00 00 00 00 00 00 00 11 22 33 00")
    static let iPhoneConnected = packet("00 0A 03 2C 00 01 41 6C 65 78 E2 80 99 73 20 69 50 68 6F 6E 65 00 00 00 00 00 00 44 55 66 01")
    static let laptop = packet("00 0A 03 2C 00 02 4C 61 70 74 6F 70 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 77 88 99 00")
    static let console = packet("00 0A 03 2C 00 03 43 6F 6E 73 6F 6C 65 00 00 00 00 00 00 00 00 00 00 00 00 00 00 AA BB CC 00")
    static let leftBatteryAck = packet("00 0A 83 06 00 64")
    static let caseBatteryAck = packet("00 0A 83 17 00 FF")

    static let androidName = "Téléphone"
    static let iPhoneName = "Alex’s iPhone"

    static func device(_ name: String, index: UInt8, connected: Bool) -> PairedDevice {
        PairedDevice(index: index, name: name, isConnected: connected)
    }
}
