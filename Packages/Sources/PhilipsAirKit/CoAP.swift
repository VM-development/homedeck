import Foundation

/// Just enough CoAP (RFC 7252) for the purifier: non-confirmable requests, Uri-Path, Observe, and decoding replies.
public enum CoAP {
    public static let port: UInt16 = 5683
    public static let get: UInt8 = 0x01
    public static let post: UInt8 = 0x02

    public enum Kind: UInt8 { case confirmable, nonConfirmable, acknowledgement, reset }

    public enum Option {
        public static let observe = 6
        public static let uriPath = 11
        public static let contentFormat = 12
        public static let maxAge = 14
    }

    public struct Message {
        public let kind: Kind
        public let code: UInt8
        public let id: UInt16
        public let token: [UInt8]
        public let options: [Int: [[UInt8]]]
        public let payload: [UInt8]

        /// Response codes print as class.detail, like 2.05 for Content.
        public var codeText: String { String(format: "%d.%02d", code >> 5, code & 31) }

        public func uint(_ option: Int) -> Int? {
            options[option]?.first.map { $0.reduce(0) { $0 << 8 | Int($1) } }
        }
    }

    /// A non-confirmable request, as the open-source clients send them. A payload goes as text (Content-Format 0).
    /// `observeValue` 0 registers for pushes, 1 cancels.
    public static func request(_ code: UInt8, id: UInt16, token: [UInt8], path: String, observe: Bool = false,
                               observeValue: UInt8 = 0, payload: [UInt8] = []) -> Data {
        var options = path.split(separator: "/").map { (Option.uriPath, Array($0.utf8)) }
        if observe { options.append((Option.observe, observeValue == 0 ? [] : [observeValue])) }
        if !payload.isEmpty { options.append((Option.contentFormat, [])) }
        return encode(.nonConfirmable, code: code, id: id, token: token, options: options, payload: payload)
    }

    /// Acknowledges a confirmable notification so the device keeps sending.
    public static func ack(id: UInt16) -> Data {
        encode(.acknowledgement, code: 0, id: id, token: [], options: [], payload: [])
    }

    static func encode(_ kind: Kind, code: UInt8, id: UInt16, token: [UInt8], options: [(Int, [UInt8])],
                       payload: [UInt8]) -> Data {
        var out: [UInt8] = [0x40 | kind.rawValue << 4 | UInt8(token.count), code, UInt8(id >> 8), UInt8(id & 0xFF)] + token
        var last = 0
        for (number, value) in options.sorted(by: { $0.0 < $1.0 }) {  // stable: path segments keep their order
            let (delta, deltaExtra) = nibble(number - last)
            let (length, lengthExtra) = nibble(value.count)
            out += [delta << 4 | length] + deltaExtra + lengthExtra + value
            last = number
        }
        if !payload.isEmpty { out += [0xFF] + payload }
        return Data(out)
    }

    private static func nibble(_ n: Int) -> (UInt8, [UInt8]) {
        n < 13 ? (UInt8(n), []) : n < 269 ? (13, [UInt8(n - 13)]) : (14, [UInt8((n - 269) >> 8), UInt8((n - 269) & 0xFF)])
    }

    public static func decode(_ data: Data) -> Message? {
        let b = [UInt8](data)
        guard b.count >= 4, b[0] >> 6 == 1, let kind = Kind(rawValue: b[0] >> 4 & 3) else { return nil }
        let tokenLength = Int(b[0] & 15)
        var i = 4 + tokenLength
        guard tokenLength <= 8, b.count >= i else { return nil }
        var options: [Int: [[UInt8]]] = [:]
        var number = 0
        func extended(_ v: Int) -> Int? {
            switch v {
            case 13: guard i < b.count else { return nil }; i += 1; return Int(b[i - 1]) + 13
            case 14: guard i + 1 < b.count else { return nil }; i += 2; return (Int(b[i - 2]) << 8 | Int(b[i - 1])) + 269
            case 15: return nil
            default: return v
            }
        }
        while i < b.count, b[i] != 0xFF {
            let header = Int(b[i])
            i += 1
            guard let delta = extended(header >> 4), let length = extended(header & 15), i + length <= b.count else { return nil }
            number += delta
            options[number, default: []].append(Array(b[i..<i + length]))
            i += length
        }
        let payload = i < b.count ? Array(b[(i + 1)...]) : []
        return Message(kind: kind, code: b[1], id: UInt16(b[2]) << 8 | UInt16(b[3]), token: Array(b[4..<4 + tokenLength]),
                       options: options, payload: payload)
    }
}
