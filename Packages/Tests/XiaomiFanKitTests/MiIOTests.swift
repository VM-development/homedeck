import XCTest
@testable import XiaomiFanKit

/// Vectors from research/xiaomi/work-cloud-fan/demo_protocols.py with a made-up token, device id and stamp.
final class MiIOTests: XCTestCase {
    let miio = MiIO(token: "00112233445566778899aabbccddeeff")!

    func testHello() {
        XCTAssertEqual(MiIO.hello.hex, "21310020" + String(repeating: "ff", count: 28))
    }

    func testRequestPacket() {
        let json = Data(#"{"id":1731500001,"method":"get_properties","params":[{"did":"power","siid":2,"piid":1}]}"#.utf8)
        XCTAssertEqual(miio.packet(json: json, did: 0x1234ABCD, stamp: 0xAB12).hex,
                       "21310080000000001234abcd0000ab128c62b725d40de889c86a1818142997b1ef6e4d3fa4e54ebf852625df18824573"
                       + "a5cbe9a844e8ebb059dbf92d27b17becbb913b0e62b401a279c02e0676c72dc5d44cc58e3c459ea4af64fb3dfb1b4b17"
                       + "61d5b36082f75179e87659261dab3a69e763f763e5c939523e46e507a2688242")
    }

    func testReply() throws {
        let packet = Data(hex: "213100b0000000001234abcd0000ab13eeccbe4ffea2231873f7dd4671af6e2555234c3c888e75634a8ae280e9fc469f07"
                          + "2491f657f39d954f2d667f74bd4007bb8ee58eebd2372c1215f9e5c2a14e9d7911601f08604edcbc66ba3c26c494321ca4"
                          + "0f690f99b8c0807e9379185d0c5f60b72a633dd585256f61845aeb9c3a3e6a8a2fd1bd04fa82ad2278556a83f4d20b432d"
                          + "592fe701ba8f46976ff95b985416c470b85b71b7bbf45f4bc6c52d19bb")
        let header = try XCTUnwrap(MiIO.header(packet))
        XCTAssertEqual(header.did, 0x1234ABCD)
        XCTAssertEqual(header.stamp, 0xAB13)
        let reply = try XCTUnwrap(Fan.Reply(XCTUnwrap(miio.open(packet))))
        XCTAssertEqual(reply.id, 7)
        let state = reply.state()
        XCTAssertTrue(state.power)
        XCTAssertEqual(state.level, 3)
        XCTAssertNil(MiIO(token: "ffeeddccbbaa99887766554433221100")!.open(packet), "a wrong token fails the checksum")
    }

    func testRequestsRoundTrip() throws {
        let read = try XCTUnwrap(JSONSerialization.jsonObject(with: Fan.read(id: 5)) as? [String: Any])
        XCTAssertEqual(read["method"] as? String, "get_properties")
        XCTAssertEqual((read["params"] as? [[String: Any]])?.count, 11)
        let write = try XCTUnwrap(JSONSerialization.jsonObject(with: Fan.write(.angle, 120, id: 6)) as? [String: Any])
        let entry = try XCTUnwrap((write["params"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["siid"] as? Int, 2)
        XCTAssertEqual(entry["piid"] as? Int, 5)
        XCTAssertEqual(entry["value"] as? Int, 120)
    }

    func testErrorsKeepThePreviousState() throws {
        let json = Data(#"{"id":9,"result":[{"did":"speed","siid":2,"piid":6,"code":-4002},{"did":"light","siid":4,"piid":1,"code":0,"value":false}]}"#.utf8)
        var before = Fan.State()
        before.speed = 40
        let after = try XCTUnwrap(Fan.Reply(json)).state(updating: before)
        XCTAssertEqual(after.speed, 40)
        XCTAssertFalse(after.light)
        XCTAssertNil(Fan.Reply(Data(#"{"id":1,"error":{"code":-9999,"message":"user ack timeout"}}"#.utf8))?.results.first)
    }
}

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map {
            UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)...].prefix(2), radix: 16)!
        })
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
