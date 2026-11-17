import XCTest
@testable import DreameKit

/// Expected values from research/dreame-l40/work/dreame_cloud.py (Tasshack's rules) with made-up keys.
final class DreameCloudTests: XCTestCase {
    let keys = DreameCloud.Keys(salt: "salt", basic: "client-blob", signing: "TEST-KEY-NOT-REA")!

    func testCanonical() {
        let command = DreameCloud.command(did: "123", id: 7, method: "get_properties", params: [["siid": 2, "piid": 1]])
        XCTAssertEqual(DreameCloud.canonical(command), #"data=[did="123"&id=7&method="get_properties"]&did=123&id=7"#)
        XCTAssertEqual(DreameCloud.canonical(["keys": ["b", "a"], "on": true, "n": NSNull(), "e": [String: Any](), "x": 3]),
                       #"e=]&keys=["b","a"]&n=null&on=true&x=3"#)
        XCTAssertEqual(DreameCloud.canonical(["a": ["b": false, "c": NSNull(), "d": 1.5, "s": "x y"]]), #"a=[b=false&c=null&d=1.5&s="x y"]"#)
    }

    func testSigned() {
        let command = DreameCloud.command(did: "123", id: 7, method: "get_properties", params: [["siid": 2, "piid": 1]])
        let body = DreameCloud.signed(command, milliseconds: 1_700_000_000_000, keys: keys)
        XCTAssertEqual(body["sign"] as? String, "10a1abb5fa9ea6b9e29fbc6fa2834c63")
        XCTAssertEqual(body["timestamp"] as? Int64, 1_700_000_000_000)
    }

    func testSignInPieces() {
        XCTAssertEqual(DreameCloud.passwordHash("pw", salt: "salt"), "55e70b9971d050fe8f7455eb551189cf")
        XCTAssertTrue(DreameCloud.loginForm(username: "a@b.c", password: "pw", keys: keys)
            .hasSuffix("username=a%40b.c&password=55e70b9971d050fe8f7455eb551189cf"))
        XCTAssertEqual(DreameCloud.meta(username: "a@b.c", visitor: "v"), "cv=a_102060700;canvasHash=88b35e4e;webglHash=863d501b;visitorIdHash=v")
        XCTAssertEqual(DreameCloud.rlc(region: "eu", lang: "en", country: "DE", keys: keys), "iTps5u8hcAjGMS+JTqDo8A==")
    }

    func testMIoT() {
        let result: [[String: Any]] = [["siid": 3, "piid": 1, "code": 0, "value": 87], ["siid": 5, "piid": 1, "code": -704030013]]
        let values = MIoT.values(result)
        XCTAssertEqual(values[MIoT(3, 1)] as? Int, 87)
        XCTAssertNil(values[MIoT(5, 1)], "an error code means the robot doesn't have it")
        let action = MIoT.action(MIoT(4, 4), did: "1", in: [(10, "2,1")])
        XCTAssertEqual(action["aiid"] as? Int, 4)
    }
}
