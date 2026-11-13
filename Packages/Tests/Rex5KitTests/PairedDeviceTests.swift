import XCTest
@testable import Rex5Kit

final class PairedDeviceTests: XCTestCase {
    func testParsesCyrillicNameAndConnectedFlag() throws {
        let device = try XCTUnwrap(PairedDevice(packet: Fixtures.androidConnected))
        XCTAssertEqual(device.index, 0)
        XCTAssertEqual(device.name, Fixtures.androidName)
        XCTAssertTrue(device.isConnected)
    }

    func testParsesCurlyApostropheName() throws {
        let device = try XCTUnwrap(PairedDevice(packet: Fixtures.iPhoneConnected))
        XCTAssertEqual(device.index, 1)
        XCTAssertEqual(device.name, Fixtures.iPhoneName)
    }

    func testParsesDisconnectedDevice() throws {
        let device = try XCTUnwrap(PairedDevice(packet: Fixtures.console))
        XCTAssertEqual(device.name, "Console")
        XCTAssertFalse(device.isConnected)
    }

    func testRejectsOtherPackets() {
        XCTAssertNil(PairedDevice(packet: Fixtures.leftBatteryAck))
        XCTAssertNil(PairedDevice(packet: GaiaPacket(command: Rex5Command.deviceList.rawValue, payload: [0, 1])))
    }

    func testAssemblerBuildsListInIndexOrder() throws {
        var assembler = DeviceListAssembler()
        for packet in [Fixtures.androidConnected, Fixtures.iPhoneConnected, Fixtures.laptop, Fixtures.console] {
            assembler.add(try XCTUnwrap(PairedDevice(packet: packet)))
        }
        XCTAssertEqual(assembler.devices.map(\.name), [Fixtures.androidName, Fixtures.iPhoneName, "Laptop", "Console"])
    }

    func testAssemblerStartsOverAtIndexZero() throws {
        var assembler = DeviceListAssembler()
        assembler.add(try XCTUnwrap(PairedDevice(packet: Fixtures.androidConnected)))
        assembler.add(try XCTUnwrap(PairedDevice(packet: Fixtures.iPhoneConnected)))
        assembler.add(try XCTUnwrap(PairedDevice(packet: Fixtures.androidDisconnected)))
        XCTAssertEqual(assembler.devices.count, 1)
        XCTAssertFalse(assembler.devices[0].isConnected)
    }

    func testBatteryAcknowledgements() {
        XCTAssertEqual(Fixtures.leftBatteryAck.responseData, [0x64])
        XCTAssertEqual(Fixtures.caseBatteryAck.responseData, [0xFF])  // unknown
    }
}
