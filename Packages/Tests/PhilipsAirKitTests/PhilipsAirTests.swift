import XCTest
@testable import PhilipsAirKit

/// Vectors from research/philips-ac2729/work/ac2729_probe.py with the made-up secret "TestSecret"
/// (the real one stays in the git-ignored Config/Secrets.xcconfig).
final class PhilipsAirTests: XCTestCase {
    let cipher = LANCipher(secret: "TestSecret")!

    func testKeyAndIVAreHexCharacters() {
        let (key, iv) = cipher.keyIV("1A2B3C4E")
        XCTAssertEqual(String(decoding: key, as: UTF8.self), "E9037929E1504AE6")
        XCTAssertEqual(String(decoding: iv, as: UTF8.self), "3C320E7DD3039E88")
    }

    func testSealPowerOn() {
        let body = Data(#"{"state":{"desired":{"CommandType":"app","DeviceId":"","EnduserId":"","pwr":"1"}}}"#.utf8)
        XCTAssertEqual(cipher.seal(body, counter: 0x1A2B3C4E),
                       "1A2B3C4E81F8B7F25BF4D28DF7A019406D6E2307CD4562861B54592E68E19946B80F367F6D180B0A6E4F115F6E04E3EED58E"
                       + "CEFF1EB7538711FC84CCAB1A16225146BBD6CB7B758349869AA23573FCCE248F427E28147EA7693F687FF52C954A8C6545"
                       + "61506DEFD578F62A00B5FBE1519401F4D428BD9C0435AAA661D96686FCC04721AC")
    }

    func testOpenStatus() throws {
        let wire = "0000ABCD1FB30E8DA439530B371982DEEB0BCCEFFE08CA8273DD841F1AC7C184D5F192AC5B0967EF698C8689E55365EA6DF32C76"
            + "265E0C7260A3979CA9B8ADBC58177527A0F5D512BFE75381BC29E15E7479D370613C75889AD1EA4C5ADB8B37554BA9C65363808DC1"
            + "03C5BB5D860292B0C16A1DACF75FFFDC88660E1D3BCFDC10B8C0F40F9B55ADCC81C10061F29F6B6673C4EC3266402F64426072D63B"
            + "6F70D3CDCC9EAC87360337BF9D71432CCAD18914D755AC2EEC33D6A3AB67184CEE7B3DB5EEB5"
        let opened = try XCTUnwrap(cipher.open(wire))
        XCTAssertEqual(opened.counter, 0xABCD)
        let state = try XCTUnwrap(Purifier.State(json: opened.plaintext))
        XCTAssertTrue(state.power)
        XCTAssertEqual(state.mode, "M")
        XCTAssertEqual(state.fanSpeed, "2")
        XCTAssertTrue(state.humidify)
        XCTAssertEqual(state.humidityTarget, 50)
        XCTAssertEqual(state.humidity, 44)
        XCTAssertEqual(state.pm25, 3)
        XCTAssertFalse(state.childLock)
        XCTAssertEqual(state.waterLevel, 100)
        XCTAssertNil(cipher.open(String(wire.dropLast()) + "0"), "a changed digest is refused")
        XCTAssertNil(LANCipher(secret: "OtherSecret")!.open(String(wire.prefix(8)) + "00" + wire.dropFirst(10)),
                     "a changed ciphertext fails the digest")
    }

    func testCounterWraps() {
        XCTAssertEqual(LANCipher.next(1), 2)
        XCTAssertEqual(LANCipher.next(2_000_000_000), 1)
    }

    func testCoAP() throws {
        let sync = CoAP.request(CoAP.post, id: 0x0102, token: [0xAA, 0xBB, 0xCC, 0xDD], path: "/sys/dev/sync",
                                payload: Array("5E1F00A2".utf8))
        XCTAssertEqual(sync.map { String(format: "%02x", $0) }.joined(),
                       "54020102aabbccddb3737973036465760473796e6310ff3545314630304132")
        let status = CoAP.request(CoAP.get, id: 0x1234, token: [0xAB, 0xCD], path: "/sys/dev/status", observe: true)
        XCTAssertEqual(status.map { String(format: "%02x", $0) }.joined(), "52011234abcd60537379730364657606737461747573")
        XCTAssertEqual(CoAP.ack(id: 0x0102).map { String(format: "%02x", $0) }.joined(), "60000102")
        let message = try XCTUnwrap(CoAP.decode(status + Data([0xFF, 0x78])))
        XCTAssertEqual(message.kind, .nonConfirmable)
        XCTAssertEqual(message.token, [0xAB, 0xCD])
        XCTAssertEqual(message.options[CoAP.Option.uriPath]?.map { String(decoding: $0, as: UTF8.self) }, ["sys", "dev", "status"])
        XCTAssertEqual(message.options[CoAP.Option.observe]?.first, [])
        XCTAssertEqual(message.payload, [0x78])
    }

    func testCommandBody() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Purifier.command(["mode": "M", "om": "2"])) as? [String: Any])
        let desired = try XCTUnwrap((json["state"] as? [String: Any])?["desired"] as? [String: Any])
        XCTAssertEqual(desired["CommandType"] as? String, "app")
        XCTAssertEqual(desired["EnduserId"] as? String, "")
        XCTAssertEqual(desired["om"] as? String, "2")
    }
}

final class PurifierStateTests: XCTestCase {
    func testTankOutSetsBit15() throws {
        let json = Data(#"{"state":{"reported":{"pwr":"1","func":"PH","err":32768,"wl":100,"cl":true,"om":"s"}}}"#.utf8)
        let state = try XCTUnwrap(Purifier.State(json: json))
        XCTAssertTrue(state.needsWater)
        XCTAssertTrue(state.childLock)
        XCTAssertFalse(try XCTUnwrap(Purifier.State(json: Data(#"{"state":{"reported":{"err":0,"wl":100}}}"#.utf8))).needsWater)
    }
}
