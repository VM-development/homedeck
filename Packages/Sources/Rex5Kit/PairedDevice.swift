/// One entry of the earbuds' paired-device list.
/// Packet: vendor (2) | 03 2C (2) | 00 | index | name (21, UTF-8, zero-padded) | 3 address bytes (unused) | connected flag.
public struct PairedDevice: Equatable, Codable, Sendable {
    public let index: UInt8
    public let name: String
    public let isConnected: Bool

    public init(index: UInt8, name: String, isConnected: Bool) {
        self.index = index
        self.name = name
        self.isConnected = isConnected
    }

    public init?(packet: GaiaPacket) {
        let p = packet.payload
        guard packet.vendor == GaiaPacket.noble,
              packet.command == Rex5Command.deviceList.rawValue,
              !packet.isAcknowledgement,
              p.count == 27 else { return nil }
        self.init(index: p[1],
                  name: String(decoding: p[2..<23].prefix { $0 != 0 }, as: UTF8.self),
                  isConnected: p[26] == 1)
    }
}

/// Collects device-list packets into a list. Index 0 starts a new list; the earbuds send indexes in order.
public struct DeviceListAssembler: Sendable {
    public private(set) var devices: [PairedDevice] = []

    public init() {}

    public mutating func add(_ device: PairedDevice) {
        if device.index == 0 { devices = [] }
        devices.removeAll { $0.index == device.index }
        devices.append(device)
        devices.sort { $0.index < $1.index }
    }
}
