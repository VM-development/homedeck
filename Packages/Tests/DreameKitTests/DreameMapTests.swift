import XCTest
@testable import DreameKit

/// Like Tasshack, the URL-safe characters are swapped before the key is split off, so test keys avoid - and _.
/// A 4×2 made-up map: zlib, then AES-256-CBC with a made-up key and IV, then URL-safe base64 (built with Python and openssl).
final class DreameMapTests: XCTestCase {
    let encrypted = "ziZoOlyMaBsGpcgj57z2l1tCTl31AQOksajqQml59inAB7qYQlTEVFCjcWH5E0hRjM6FUBUV0bb7fiM9ihLn8jdOdO22fuKEpd8Mkg-f_hsBIV8EGOCCFyN7nXuzMkP-QJV73NQLlvvhdiLrMreT9w=="
    let plain = "eJxjZ2Bk8ExhOPc_igECjBhYGJgYLP7P-c_AyNjExNTIUK1UnJoen5mXpmRVrWQIIkoqC1KVrEx0lDLzUlIrlKwManWUjBASBjpKeYm5QIZSiFFUbmK4X45SbW0tAHRCHNg="

    func check(_ map: DreameMap?) throws {
        let map = try XCTUnwrap(map)
        XCTAssertEqual(map.mapID, 7)
        XCTAssertEqual(map.frameType, "I")
        XCTAssertEqual(map.width, 4)
        XCTAssertEqual(map.height, 2)
        XCTAssertEqual(map.gridSize, 50)
        XCTAssertEqual(map.left, -200)
        XCTAssertEqual(map.robot.x, 100)
        XCTAssertEqual(map.robot.y, -50)
        XCTAssertEqual(map.pixels, [0, 1, 1, 0x82, 2, 2, 0x81, 0])
        XCTAssertEqual(map.rooms, [.init(id: 1, name: "Kitchen", type: 4), .init(id: 2, name: "Office", type: 0)])
    }

    func testEncryptedWithKeyFromObjectName() throws {
        try check(DreameMap(text: encrypted, key: "madeupkey", iv: "MadeUpIV12345678"))
    }

    func testKeyAfterComma() throws {
        try check(DreameMap(text: encrypted + ",madeupkey", iv: "MadeUpIV12345678"))
    }

    func testPlain() throws {
        try check(DreameMap(text: plain, iv: nil))
    }

    func testWrongKeyFails() {
        XCTAssertNil(DreameMap(text: encrypted, key: "other-key", iv: "MadeUpIV12345678"))
    }

    func testPixelFormats() throws {
        let map = try XCTUnwrap(DreameMap(text: plain, iv: nil))  // no fsm, no version-3 keys: 6-bit rooms
        XCTAssertEqual(map.cell(0x82), .room(2, edge: true))
        XCTAssertEqual(map.cell(0x81), .room(1, edge: true))
        XCTAssertEqual(map.cell(0), .outside)
    }
}
