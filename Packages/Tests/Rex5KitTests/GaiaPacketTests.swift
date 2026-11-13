import XCTest
@testable import Rex5Kit

final class GaiaPacketTests: XCTestCase {
    func testCommandIDsArePinned() {
        XCTAssertEqual(Rex5Command.allCases.map(\.rawValue), [0x0306, 0x0307, 0x0309, 0x0314, 0x0315, 0x032A, 0x032C])
    }

    func testEncodesCommandWithNobleVendor() {
        XCTAssertEqual(GaiaPacket(command: Rex5Command.leftBattery.rawValue).bytes, [0x00, 0x0A, 0x03, 0x06])
    }

    func testEncodesPayloadAfterHeader() {
        XCTAssertEqual(GaiaPacket(command: Rex5Command.disconnectDevice.rawValue, payload: [0x01]).bytes,
                       [0x00, 0x0A, 0x03, 0x2A, 0x01])
    }

    func testDecodesAcknowledgementStatusAndData() throws {
        let packet = try XCTUnwrap(GaiaPacket(bytes: [0x00, 0x0A, 0x83, 0x06, 0x00, 0x50]))
        XCTAssertTrue(packet.isAcknowledgement)
        XCTAssertEqual(packet.command, 0x0306)
        XCTAssertEqual(packet.status, 0x00)
        XCTAssertEqual(packet.responseData, [0x50])
    }

    func testAcknowledgementRoundTrips() throws {
        let bytes: [UInt8] = [0x00, 0x0A, 0x83, 0x2C, 0x00, 0x01, 0x02]
        XCTAssertEqual(try XCTUnwrap(GaiaPacket(bytes: bytes)).bytes, bytes)
    }

    func testRejectsPacketShorterThanHeader() {
        XCTAssertNil(GaiaPacket(bytes: [0x00, 0x0A, 0x03]))
    }

    func testCommandHasNoStatus() {
        XCTAssertNil(GaiaPacket(command: 0x0306, payload: [0x00]).status)
    }

    func testHexFormatting() {
        XCTAssertEqual([UInt8]([0x0A, 0xFF]).hex, "0A FF")
        XCTAssertEqual([UInt8]().hex, "(empty)")
    }

    func testRecognisesRepliesInBothGaiaStyles() {
        let battery = GaiaPacket(command: 0x0306)
        XCTAssertTrue(GaiaPacket(bytes: [0x00, 0x0A, 0x83, 0x06, 0x00, 0x64])!.isReply(to: battery))
        XCTAssertFalse(GaiaPacket(bytes: [0x00, 0x0A, 0x83, 0x07, 0x00, 0x64])!.isReply(to: battery))
        XCTAssertFalse(GaiaPacket(bytes: [0x00, 0x0A, 0x03, 0x06])!.isReply(to: battery))  // not an acknowledgement

        let band = GaiaPacket(vendor: GaiaPacket.qtilV3, command: 0x0E01)
        XCTAssertTrue(GaiaPacket(bytes: [0x00, 0x1D, 0x0F, 0x01])!.isReply(to: band))        // v3 response
        XCTAssertTrue(GaiaPacket(bytes: [0x00, 0x1D, 0x0F, 0x81, 0x01])!.isReply(to: band))  // v3 error
        XCTAssertFalse(GaiaPacket(bytes: [0x00, 0x1D, 0x0E, 0x81])!.isReply(to: band))       // v3 notification
        XCTAssertFalse(GaiaPacket(bytes: [0x00, 0x0A, 0x8E, 0x01, 0x01])!.isReply(to: band)) // other vendor
    }
}
