import CommonCrypto
import Compression
import CryptoKit
import Foundation

/// A Dreame map frame (Tasshack's decoder): URL-safe base64, optionally AES-256-CBC (key = first 32 hex characters of
/// SHA-256 of the file's key, IV = a fixed per-model string), zlib; then a 27-byte header, one byte per pixel, JSON.
public struct DreameMap {
    public struct Room: Equatable, Identifiable {
        public let id: Int
        public let name: String
        public let type: Int

        public init(id: Int, name: String, type: Int) { (self.id, self.name, self.type) = (id, name, type) }
    }

    public let mapID, frameID: Int
    public let frameType: Character
    public let width, height, gridSize, left, top: Int
    public let robot, charger: (x: Int, y: Int)
    public let pixels: [UInt8]
    public let json: [String: Any]

    /// `text` may end in ",<key>"; a file's key comes with its object name instead.
    public init?(text: String, key: String? = nil, iv: String?) {
        var body = text.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
        var key = key
        if key == nil, let comma = body.firstIndex(of: ",") {
            key = String(body[body.index(after: comma)...])
            body = String(body[..<comma])
        }
        body += String(repeating: "=", count: (4 - body.count % 4) % 4)
        guard var data = Data(base64Encoded: body) else { return nil }
        if let key, let iv {
            guard let plain = Self.decrypt(data, key: key, iv: iv) else { return nil }
            data = plain
        }
        guard let raw = Self.inflate(data), raw.count >= 27 else { return nil }
        let b = [UInt8](raw)
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        func i16(_ i: Int) -> Int { Int(Int16(bitPattern: UInt16(u16(i)))) }
        (mapID, frameID, frameType) = (u16(0), u16(2), Character(UnicodeScalar(b[4])))
        robot = (i16(5), i16(7))
        charger = (i16(11), i16(13))
        (gridSize, width, height, left, top) = (u16(17), u16(19), u16(21), i16(23), i16(25))
        let end = 27 + width * height
        guard b.count >= end else { return nil }
        pixels = Array(b[27..<end])
        json = (try? JSONSerialization.jsonObject(with: Data(b[end...])) as? [String: Any]) ?? [:]
    }

    /// Rooms from `seg_inf`: a custom name (base64) or the room type's name, numbered like the Dreamehome app.
    public var rooms: [Room] {
        guard let info = json["seg_inf"] as? [String: [String: Any]] else { return [] }
        return info.compactMap { key, value -> Room? in
            guard let id = Int(key) else { return nil }
            let type = value["type"] as? Int ?? 0
            let index = value["index"] as? Int ?? 0
            if let encoded = value["name"] as? String, let data = Data(base64Encoded: encoded), let name = String(data: data, encoding: .utf8),
               !name.isEmpty {
                return Room(id: id, name: name, type: type)
            }
            if type != 0, let typeName = Self.roomTypes[type] {
                return Room(id: id, name: index > 0 ? "\(typeName) \(index + 1)" : typeName, type: type)
            }
            return Room(id: id, name: "Room \(id)", type: type)
        }.sorted { $0.id < $1.id }
    }

    /// The map saved with room names, which a live frame carries base64-encoded (unencrypted) under "rism".
    public var savedMap: DreameMap? { (json["rism"] as? String).flatMap { DreameMap(text: $0, iv: nil) } }

    /// Rooms of this frame, or of the saved map inside it.
    public var allRooms: [Room] { rooms.isEmpty ? savedMap?.rooms ?? [] : rooms }

    public enum Cell: Equatable { case outside, floor, wall, room(Int, edge: Bool) }

    /// Tasshack's three I-frame pixel formats: "fsm" = 1 frames store room × 4 (63 wall, 62 floor, low bits 3 = carpet);
    /// version-3 maps (saveMapId, cover, diff or curtain in the JSON) use 5 bits of room, 2 of wall, 1 of carpet;
    /// the rest 6 bits of room and a top edge bit.
    public func cell(_ p: UInt8) -> Cell {
        guard p != 0 else { return .outside }
        if json["fsm"] as? Int == 1 {
            switch Int(p >> 2) {
            case 63: return .wall
            case 61, 62, 0: return .floor
            case let room: return .room(room, edge: false)
            }
        }
        if ["saveMapId", "cover", "diff", "curtain"].contains(where: { json[$0] != nil }) {
            let room = Int(p & 0x1F)
            let wall = Int(p >> 5) & 0x03
            if room == 31 || room == 0 { return wall > 0 && wall < 3 ? .wall : .floor }
            return wall == 1 || wall == 2 ? .wall : .room(room, edge: wall == 3)
        }
        let room = Int(p & 0x3F)
        if room == 0 || room >= 61 { return p & 0x80 != 0 ? .wall : .floor }
        return .room(room, edge: p & 0x80 != 0)
    }

    public static let roomTypes = [1: "Living Room", 2: "Primary Bedroom", 3: "Study", 4: "Kitchen", 5: "Dining Hall", 6: "Bathroom",
                                   7: "Balcony", 8: "Corridor", 9: "Utility Room", 10: "Closet", 11: "Meeting Room", 12: "Office",
                                   13: "Fitness Area", 14: "Recreation Area", 15: "Secondary Bedroom"]

    static func decrypt(_ data: Data, key: String, iv: String) -> Data? {
        let hex = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let aesKey = Array(hex.prefix(32).utf8)
        let ivBytes = Array(iv.utf8)
        guard ivBytes.count == 16, data.count % 16 == 0 else { return nil }
        let input = [UInt8](data)
        var output = [UInt8](repeating: 0, count: input.count)
        var written = 0
        // No padding option: like Tasshack, keep whatever follows the zlib stream; inflating ignores it.
        let status = CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0, aesKey, aesKey.count, ivBytes,
                             input, input.count, &output, output.count, &written)
        return status == kCCSuccess ? Data(output.prefix(written)) : nil
    }

    /// zlib (2-byte header, raw deflate, checksum); Apple's decoder wants only the raw deflate part.
    static func inflate(_ data: Data) -> Data? {
        guard data.count > 6, data[data.startIndex] & 0x0F == 8 else { return nil }
        let source = [UInt8](data.dropFirst(2))
        var capacity = max(source.count * 8, 1 << 16)
        while capacity <= 64 << 20 {
            var output = [UInt8](repeating: 0, count: capacity)
            let n = compression_decode_buffer(&output, capacity, source, source.count, nil, COMPRESSION_ZLIB)
            if n == 0 { return nil }
            if n < capacity { return Data(output.prefix(n)) }
            capacity *= 4  // filled the buffer: it may be cut short, so try a bigger one
        }
        return nil
    }
}
