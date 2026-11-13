import XCTest
@testable import Rex5Kit

final class TakeoverDetectorTests: XCTestCase {
    let me = Fixtures.iPhoneName
    let flip = Fixtures.androidName

    func list(iPhone: Bool, android: Bool) -> [PairedDevice] {
        [Fixtures.device(me, index: 0, connected: iPhone), Fixtures.device(flip, index: 1, connected: android)]
    }

    func testAndroidPhoneConnectingWhileIPhoneConnectedAlerts() {
        XCTAssertEqual(TakeoverDetector.newcomers(previous: list(iPhone: true, android: false),
                                                  current: list(iPhone: true, android: true), thisPhoneName: me), [flip])
    }

    func testIPhoneReconnectingDoesNotAlert() {
        XCTAssertEqual(TakeoverDetector.newcomers(previous: list(iPhone: false, android: true),
                                                  current: list(iPhone: true, android: true), thisPhoneName: me), [])
    }

    func testAndroidPhoneConnectingWhileIPhoneDisconnectedDoesNotAlert() {
        XCTAssertEqual(TakeoverDetector.newcomers(previous: list(iPhone: false, android: false),
                                                  current: list(iPhone: false, android: true), thisPhoneName: me), [])
    }

    func testAlreadyConnectedDeviceDoesNotAlertAgain() {
        XCTAssertEqual(TakeoverDetector.newcomers(previous: list(iPhone: true, android: true),
                                                  current: list(iPhone: true, android: true), thisPhoneName: me), [])
    }

    func testWithoutThisPhoneChoiceNothingAlerts() {
        XCTAssertEqual(TakeoverDetector.newcomers(previous: list(iPhone: true, android: false),
                                                  current: list(iPhone: true, android: true), thisPhoneName: nil), [])
    }

    func testRealCapturedTransition() throws {
        // Run 1 at 118 s: the Android phone dropped. The reverse transition must alert.
        let before = [try XCTUnwrap(PairedDevice(packet: Fixtures.androidDisconnected)), try XCTUnwrap(PairedDevice(packet: Fixtures.iPhoneConnected))]
        let after = [try XCTUnwrap(PairedDevice(packet: Fixtures.androidConnected)), try XCTUnwrap(PairedDevice(packet: Fixtures.iPhoneConnected))]
        XCTAssertEqual(TakeoverDetector.newcomers(previous: before, current: after, thisPhoneName: me), [flip])
        XCTAssertEqual(TakeoverDetector.newcomers(previous: after, current: before, thisPhoneName: me), [])
    }
}
