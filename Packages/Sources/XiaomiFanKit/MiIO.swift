import CommonCrypto
import CryptoKit
import Foundation

/// Xiaomi's local miIO protocol: UDP port 54321, a 32-byte header, then JSON encrypted with AES-128-CBC
/// keyed from the device's 16-byte token. Header: magic 2131, length, device id (64 bit), stamp, MD5 checksum.
public struct MiIO {
    public static let port: UInt16 = 54321
    /// Asks the device for its id and clock ("stamp"); every request must carry a fresh stamp.
    public static let hello = Data([0x21, 0x31, 0x00, 0x20] + [UInt8](repeating: 0xFF, count: 28))

    private let token: [UInt8]
    private let key: [UInt8]
    private let iv: [UInt8]

    /// The token as 32 hex characters (separators allowed), as Xiaomi Cloud Tokens Extractor prints it.
    public init?(token text: String) {
        let hex = text.filter(\.isHexDigit)
        guard hex.count == 32 else { return nil }
        token = stride(from: 0, to: 32, by: 2).map { i in
            UInt8(hex[hex.index(hex.startIndex, offsetBy: i)...].prefix(2), radix: 16)!
        }
        key = Array(Insecure.MD5.hash(data: token))
        iv = Array(Insecure.MD5.hash(data: key + token))
    }

    /// Device id and stamp from any packet's header (the hello reply carries nothing else).
    public static func header(_ packet: Data) -> (did: UInt64, stamp: UInt32)? {
        let p = [UInt8](packet)
        guard p.count >= 32, p[0] == 0x21, p[1] == 0x31 else { return nil }
        let did = p[4..<12].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let stamp = p[12..<16].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return (did, stamp)
    }

    public func packet(json: Data, did: UInt64, stamp: UInt32) -> Data {
        let body = crypt(Array(json), CCOperation(kCCEncrypt))!
        let length = 32 + body.count
        var p: [UInt8] = [0x21, 0x31, UInt8(length >> 8), UInt8(length & 0xFF)]
        p += (0..<8).reversed().map { UInt8(did >> ($0 * 8) & 0xFF) }
        p += (0..<4).reversed().map { UInt8(stamp >> ($0 * 8) & 0xFF) }
        p += token + body
        p.replaceSubrange(16..<32, with: Array(Insecure.MD5.hash(data: p)))
        return Data(p)
    }

    /// The JSON inside a reply, or nil when the checksum fails: the token is wrong (or changed when the fan was re-added).
    public func open(_ packet: Data) -> Data? {
        var p = [UInt8](packet)
        guard p.count > 32, Self.header(packet) != nil else { return nil }
        let checksum = Array(p[16..<32])
        p.replaceSubrange(16..<32, with: token)
        guard Array(Insecure.MD5.hash(data: p)) == checksum, var json = crypt(Array(p[32...]), CCOperation(kCCDecrypt))
        else { return nil }
        while json.last == 0 { json.removeLast() }  // some devices end the JSON with a zero byte
        return Data(json)
    }

    private func crypt(_ input: [UInt8], _ operation: CCOperation) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, input, input.count, &output, output.count, &written)
        return status == kCCSuccess ? Array(output.prefix(written)) : nil
    }
}
