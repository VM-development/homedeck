import Foundation

/// A GAIA V1/V2 packet as written to, and notified from, the GAIA GATT characteristics.
/// Layout (big-endian): vendor (2) | command (2, bit 15 = acknowledgement) | payload.
public struct GaiaPacket: Equatable, Sendable {
    public static let noble: UInt16 = 0x000A
    /// Qualcomm's GAIA v3 vendor. Its command field is feature (7 bits) | type (2) | id (7): 0 command, 1 notification, 2 response, 3 error.
    public static let qtilV3: UInt16 = 0x001D
    static let ackFlag: UInt16 = 0x8000

    public let vendor: UInt16
    public let command: UInt16
    public let isAcknowledgement: Bool
    public let payload: [UInt8]

    public init(vendor: UInt16 = GaiaPacket.noble, command: UInt16, isAcknowledgement: Bool = false, payload: [UInt8] = []) {
        self.vendor = vendor
        self.command = command & 0x7FFF
        self.isAcknowledgement = isAcknowledgement
        self.payload = payload
    }

    public init?(bytes: [UInt8]) {
        guard bytes.count >= 4 else { return nil }
        let raw = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        self.init(vendor: UInt16(bytes[0]) << 8 | UInt16(bytes[1]),
                  command: raw,
                  isAcknowledgement: raw & Self.ackFlag != 0,
                  payload: Array(bytes.dropFirst(4)))
    }

    public var bytes: [UInt8] {
        let raw = isAcknowledgement ? command | Self.ackFlag : command
        return [UInt8(vendor >> 8), UInt8(vendor & 0xFF), UInt8(raw >> 8), UInt8(raw & 0xFF)] + payload
    }

    /// Status byte of an acknowledgement. 0 means success.
    public var status: UInt8? { isAcknowledgement ? payload.first : nil }

    /// True when this packet answers `request`: a v3 response or error for v3, an acknowledgement otherwise.
    public func isReply(to request: GaiaPacket) -> Bool {
        guard vendor == request.vendor else { return false }
        if vendor == Self.qtilV3 {
            return command & 0xFE7F == request.command & 0xFE7F && command & 0x0100 != 0
        }
        return isAcknowledgement && command == request.command
    }

    /// Acknowledgement data after the status byte.
    public var responseData: [UInt8] { Array(payload.dropFirst()) }
}

extension Array where Element == UInt8 {
    public var hex: String { isEmpty ? "(empty)" : map { String(format: "%02X", $0) }.joined(separator: " ") }
}
