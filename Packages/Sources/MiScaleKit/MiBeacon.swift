import CommonCrypto
import Foundation

/// A Xiaomi "MiBeacon" frame: the service data under UUID FE95 in a Bluetooth advertisement.
/// The S400 sends each weigh-in as an encrypted v5 frame; decrypting needs the scale's bind key and MAC.
/// Layout and evidence: docs/devices/mi-scale-s400/protocol.md.
public struct MiBeacon: Sendable {
    public static let serviceUUID = "FE95"
    /// Every S400 / S400 Pro product id (colour and region variants).
    public static let s400ProductIDs: Set<UInt16> = [0x30D9, 0x3BD5, 0x48CF, 0x4FC2, 0x4B05, 0x78BD]
    static let measurementObject: UInt16 = 0x6E16

    public let frameControl: UInt16
    public let productID: UInt16
    public let counter: UInt8
    private let bytes: [UInt8]
    private let payloadOffset: Int

    public var isEncrypted: Bool { frameControl & 0x0008 != 0 }
    public var hasMAC: Bool { frameControl & 0x0010 != 0 }
    public var hasObjects: Bool { frameControl & 0x0040 != 0 }
    public var version: Int { Int(frameControl >> 12) }

    public init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 5 else { return nil }
        bytes = b
        frameControl = UInt16(b[0]) | UInt16(b[1]) << 8
        productID = UInt16(b[2]) | UInt16(b[3]) << 8
        counter = b[4]
        var offset = 5
        if frameControl & 0x0010 != 0 { offset += 6 }        // MAC, byte-reversed
        if frameControl & 0x0020 != 0 {                      // capability byte, maybe 2 IO bytes after it
            guard b.count > offset else { return nil }
            offset += b[offset] & 0x20 != 0 ? 3 : 1
        }
        guard b.count >= offset else { return nil }
        payloadOffset = offset
    }

    /// The scale's MAC, in display order, when the frame carries it (the S400's unencrypted idle frames do).
    public var mac: [UInt8]? { hasMAC && bytes.count >= 11 ? Array(bytes[5..<11].reversed()) : nil }

    /// Hex of the frame with the MAC bytes blanked, for the shareable log.
    public var redactedHex: String {
        bytes.enumerated().map { hasMAC && (5..<11).contains($0.offset) ? "xx" : String(format: "%02x", $0.element) }.joined()
    }

    /// Decrypted objects (id, value), or nil when the frame isn't an encrypted v4/v5 frame or the key or MAC is wrong.
    public func objects(key: [UInt8], mac: [UInt8]) -> [(id: UInt16, value: [UInt8])]? {
        guard isEncrypted, hasObjects, version >= 4, key.count == 16, mac.count == 6,
              bytes.count >= payloadOffset + 7 else { return nil }
        // Nonce: MAC reversed, product id and counter as sent, the 3-byte extended counter before the 4-byte tag.
        let nonce = mac.reversed() + bytes[2..<5] + bytes[(bytes.count - 7)..<(bytes.count - 4)]
        guard let plain = AESCCM.decrypt(key: key, nonce: Array(nonce),
                                         ciphertext: Array(bytes[payloadOffset..<(bytes.count - 7)]),
                                         tag: Array(bytes.suffix(4)), aad: [0x11]) else { return nil }
        var result: [(UInt16, [UInt8])] = []
        var i = 0
        while i + 3 <= plain.count {
            let id = UInt16(plain[i]) | UInt16(plain[i + 1]) << 8
            let end = min(plain.count, i + 3 + Int(plain[i + 2]))
            result.append((id, Array(plain[(i + 3)..<end])))
            i = end
        }
        return result
    }

    /// Parses "AA:BB:…" or plain hex, ignoring colons, dashes and spaces.
    public static func hexBytes(_ text: String, count: Int) -> [UInt8]? {
        let digits = text.filter { !":- ".contains($0) }
        guard digits.count == count * 2 else { return nil }
        var out: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }
}

/// One S400 measurement object (0x6E16).
public struct S400Reading: Equatable, Sendable {
    /// The scale's own user slot; 0 when it didn't recognise the person.
    public let profileID: Int
    /// Kilograms; nil in the frame that carries only the second impedance.
    public let weight: Double?
    public let heartRate: Int?
    /// Ohms. The weight frame carries the 50 kHz value, the frame after it the 250 kHz one.
    public let impedance: Double?
    /// Seconds since 1970 on the scale's clock; the same for every frame of one weigh-in.
    public let timestamp: UInt32

    public var isReset: Bool { weight == nil && heartRate == nil && impedance == nil }

    public init?(_ value: [UInt8]) {
        guard value.count >= 9 else { return nil }
        func u32(_ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(value[at + $1]) << (8 * $1) } }
        let packed = u32(1)
        let mass = packed & 0x7FF            // 0.1 kg; 0x7FF means "no weight" on the S400 Pro
        let pulse = (packed >> 11) & 0x7F     // bpm - 50; 0 or 127 when not measured
        let ohms = packed >> 18               // 0.1 ohm
        profileID = Int(value[0])
        weight = mass == 0 || mass == 0x7FF ? nil : Double(mass) / 10
        heartRate = pulse == 0 || pulse == 127 ? nil : Int(pulse) + 50
        impedance = ohms == 0 ? nil : Double(ohms) / 10
        timestamp = u32(5)
    }

    public static func readings(in objects: [(id: UInt16, value: [UInt8])]) -> [S400Reading] {
        objects.filter { $0.id == MiBeacon.measurementObject }.compactMap { S400Reading($0.value) }
    }
}

/// AES-128-CCM decryption (RFC 3610) on top of CommonCrypto's single-block AES: CryptoKit has no CCM.
enum AESCCM {
    static func decrypt(key: [UInt8], nonce: [UInt8], ciphertext: [UInt8], tag: [UInt8], aad: [UInt8]) -> [UInt8]? {
        let l = 15 - nonce.count
        func counterBlock(_ i: Int) -> [UInt8] {
            [UInt8(l - 1)] + nonce + (0..<l).map { UInt8(truncatingIfNeeded: i >> (8 * (l - 1 - $0))) }
        }
        var plain: [UInt8] = []
        for (n, start) in stride(from: 0, to: ciphertext.count, by: 16).enumerated() {
            let stream = block(key, counterBlock(n + 1))
            plain += zip(ciphertext[start..<min(start + 16, ciphertext.count)], stream).map { $0 ^ $1 }
        }
        // CBC-MAC over B0, the AAD with its 2-byte length, then the plaintext, each zero-padded to 16 bytes.
        let flags = UInt8((aad.isEmpty ? 0 : 0x40) | ((tag.count - 2) / 2) << 3 | (l - 1))
        let b0 = [flags] + nonce + (0..<l).map { UInt8(truncatingIfNeeded: plain.count >> (8 * (l - 1 - $0))) }
        func padded(_ part: [UInt8]) -> [UInt8] { part + [UInt8](repeating: 0, count: (16 - part.count % 16) % 16) }
        let header = aad.isEmpty ? [] : padded([UInt8(aad.count >> 8), UInt8(aad.count & 0xFF)] + aad)
        let macInput = b0 + header + padded(plain)
        var x = [UInt8](repeating: 0, count: 16)
        for start in stride(from: 0, to: macInput.count, by: 16) {
            x = block(key, zip(x, macInput[start..<(start + 16)]).map { $0 ^ $1 })
        }
        let expected = zip(x.prefix(tag.count), block(key, counterBlock(0))).map { $0 ^ $1 }
        return expected == tag ? plain : nil
    }

    static func block(_ key: [UInt8], _ input: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 16 + kCCBlockSizeAES128)
        let capacity = out.count
        var moved = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                             key, key.count, nil, input, 16, &out, capacity, &moved)
        precondition(status == kCCSuccess, "AES block failed: \(status)")
        return Array(out.prefix(16))
    }
}
