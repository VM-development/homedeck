import CommonCrypto
import CryptoKit
import Foundation

/// The purifier's local encryption. Each message is `counter ‖ ciphertext ‖ digest` as uppercase hex text:
/// key and IV are the two halves of MD5(secret + counter) as hex characters (not decoded), AES-128-CBC,
/// and the digest is SHA-256 over counter + ciphertext. The secret is the same for every unit; HomeDeck keeps it
/// out of the repo (Config/Secrets.xcconfig).
public struct LANCipher {
    private let secret: String

    public init?(secret: String) {
        guard !secret.isEmpty else { return nil }
        self.secret = secret
    }

    /// The device counts 1...2,000,000,000 and wraps to 1.
    public static func next(_ counter: UInt32) -> UInt32 { counter >= 2_000_000_000 ? 1 : counter + 1 }

    public func seal(_ plaintext: Data, counter: UInt32) -> String {
        let c = String(format: "%08X", counter)
        let ciphertext = Self.hex(crypt([UInt8](plaintext), counter: c, CCOperation(kCCEncrypt))!)
        return c + ciphertext + Self.hex(Array(SHA256.hash(data: Data((c + ciphertext).utf8))))
    }

    /// Nil when the digest or the padding is wrong.
    public func open(_ text: String) -> (counter: UInt32, plaintext: Data)? {
        let t = Array(text.utf8)
        guard t.count > 72, (t.count - 72) % 32 == 0 else { return nil }
        let c = String(decoding: t[..<8], as: UTF8.self)
        let ciphertext = String(decoding: t[8..<(t.count - 64)], as: UTF8.self)
        let digest = String(decoding: t[(t.count - 64)...], as: UTF8.self)
        guard Self.hex(Array(SHA256.hash(data: Data((c + ciphertext).utf8)))) == digest.uppercased(),
              let counter = UInt32(c, radix: 16), let bytes = Self.bytes(ciphertext),
              let plaintext = crypt(bytes, counter: c, CCOperation(kCCDecrypt)) else { return nil }
        return (counter, Data(plaintext))
    }

    func keyIV(_ counterHex: String) -> (key: [UInt8], iv: [UInt8]) {
        let digest = Array(Self.hex(Array(Insecure.MD5.hash(data: Data((secret + counterHex).utf8)))).utf8)
        return (Array(digest[..<16]), Array(digest[16...]))
    }

    private func crypt(_ input: [UInt8], counter: String, _ operation: CCOperation) -> [UInt8]? {
        let (key, iv) = keyIV(counter)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let status = CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                             key, key.count, iv, input, input.count, &output, output.count, &written)
        return status == kCCSuccess ? Array(output.prefix(written)) : nil
    }

    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined() }

    static func bytes(_ hex: String) -> [UInt8]? {
        let h = Array(hex.utf8)
        guard h.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        for i in stride(from: 0, to: h.count, by: 2) {
            guard let byte = UInt8(String(decoding: h[i..<i + 2], as: UTF8.self), radix: 16) else { return nil }
            out.append(byte)
        }
        return out
    }
}
