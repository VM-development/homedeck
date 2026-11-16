import XCTest
@testable import WalkingPadKit

/// Frames captured from a real WalkingPad C2 (2026-11-16); they carry no names or addresses.
final class WalkingPadTests: XCTestCase {
    func testCommandFrames() {
        XCTAssertEqual(WalkingPad.askStatus.hex, "f7a20000a2fd")
        XCTAssertEqual(WalkingPad.start.hex, "f7a20401a7fd")
        XCTAssertEqual(WalkingPad.stop.hex, "f7a20100a3fd")
        XCTAssertEqual(WalkingPad.setMode(.automatic).hex, "f7a20200a4fd")
        XCTAssertEqual(WalkingPad.setMode(.manual).hex, "f7a20201a5fd")
        XCTAssertEqual(WalkingPad.setMode(.standby).hex, "f7a20202a6fd")
        XCTAssertEqual(WalkingPad.setSpeed(2.0).hex, "f7a20114b7fd")
        XCTAssertEqual(WalkingPad.setSpeed(2.5).hex, "f7a20119bcfd")
    }

    func testSpeedIsClamped() {
        XCTAssertEqual(WalkingPad.setSpeed(9), WalkingPad.setSpeed(6))
        XCTAssertEqual(WalkingPad.setSpeed(0), WalkingPad.setSpeed(0.5))
    }

    func testStandby() {
        let reply = WalkingPad.decode(Data(hex: "f8a204000200000000000000000000000000a8fd"))
        XCTAssertEqual(reply, .status(.init(beltState: 4, speed: 0, mode: 2, seconds: 0, meters: 0, steps: 0)))
    }

    func testWalking() {
        // 2.0 km/h, manual, 133 s, 6 x 10 m, 173 steps.
        let reply = WalkingPad.decode(Data(hex: "f8a20114010000850000060000ad00000300f3fd"))
        XCTAssertEqual(reply, .status(.init(beltState: 1, speed: 2.0, mode: 1, seconds: 133, meters: 60, steps: 173)))
        guard case .status(let status)? = reply else { return }
        XCTAssertTrue(status.isRunning)
    }

    func testCountdown() {
        guard case .status(let status)? = WalkingPad.decode(Data(hex: "f8a209000100000c00000000000a00000300c5fd")) else {
            return XCTFail("not a status")
        }
        XCTAssertTrue(status.isCountingDown)
        XCTAssertFalse(status.isRunning)
    }

    func testOtherFrames() {
        // Settings reply, and the C2's empty answer to "newest stored walk".
        XCTAssertEqual(WalkingPad.decode(Data(hex: "f8a600000000003c1400021f00003c00000053fd")), .other(type: 0xA6))
        XCTAssertEqual(WalkingPad.decode(Data(hex: "f8a700000000000000000000000000000000a7fd")), .other(type: 0xA7))
    }

    func testRejectsBadFrames() {
        XCTAssertNil(WalkingPad.decode(Data(hex: "f8a20114010000850000060000ad00000300f4fd")))  // checksum off by one
        XCTAssertNil(WalkingPad.decode(Data(hex: "f8a2011401")))
    }
}

private extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map {
            let i = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[i...hex.index(after: i)], radix: 16)!
        })
    }
}
