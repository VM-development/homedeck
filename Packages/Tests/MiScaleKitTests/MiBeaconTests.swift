import XCTest
@testable import MiScaleKit

/// Published S400 test frames with their public test keys and made-up MACs, from Bluetooth-Devices/xiaomi-ble
/// (Apache-2.0, tests/test_parser.py).
final class MiBeaconTests: XCTestCase {
    let key1 = MiBeacon.hexBytes("0728974d657a4b60964c1b1677f35f7c", count: 16)!
    let mac1 = MiBeacon.hexBytes("8C:D0:B2:F6:BE:EF", count: 6)!

    func reading(_ hex: String, key: [UInt8], mac: [UInt8]) -> S400Reading? {
        guard let beacon = MiBeacon(Data(MiBeacon.hexBytes(hex, count: hex.count / 2)!)),
              let objects = beacon.objects(key: key, mac: mac) else { return nil }
        return S400Reading.readings(in: objects).first
    }

    func testWeighIn() throws {
        let r = try XCTUnwrap(reading("4859d53b0abc078ff2348c844138e930220000009e538599", key: key1, mac: mac1))
        XCTAssertEqual(r, try XCTUnwrap(S400Reading([0x01, 0xBB, 0x52, 0xE1, 0x54, 0xED, 0x26, 0xF7, 0x67])))
        XCTAssertEqual(r.profileID, 1)
        XCTAssertEqual(r.weight, 69.9)
        XCTAssertEqual(r.heartRate, 92)
        XCTAssertEqual(r.impedance, 543.2)
        XCTAssertEqual(r.timestamp, 1_744_250_605)
    }

    func testSecondImpedance() throws {
        let r = try XCTUnwrap(reading("4859d53b0bd6ef0b25db72785e7e2f46d6000000d8642df6", key: key1, mac: mac1))
        XCTAssertNil(r.weight)
        XCTAssertNil(r.heartRate)
        XCTAssertEqual(r.impedance, 497.6)
        XCTAssertEqual(r.timestamp, 1_744_250_605)
    }

    func testSocksAndReset() throws {
        let key = MiBeacon.hexBytes("02d2900363ef629c736a4549677acbee", count: 16)!
        let mac = MiBeacon.hexBytes("04:AE:47:67:C6:7C", count: 6)!
        let socks = try XCTUnwrap(reading("4859d53b71530438b5894b242c209908da000000479ecda3", key: key, mac: mac))
        XCTAssertEqual(socks.weight, 74.7)
        XCTAssertNil(socks.impedance)
        let reset = try XCTUnwrap(reading("4859d53b72036c6794355a19dbc864bfb3000000e4151dc8", key: key, mac: mac))
        XCTAssertTrue(reset.isReset)
    }

    func testWrongMACFailsTheTag() {
        XCTAssertNil(reading("4859d53b0abc078ff2348c844138e930220000009e538599", key: key1, mac: [0, 0, 0, 0, 0, 0]))
    }

    func testHeaderAndRedaction() throws {
        let beacon = try XCTUnwrap(MiBeacon(Data(MiBeacon.hexBytes("1059c24f04563412" + "38c1a4", count: 11)!)))
        XCTAssertTrue(beacon.hasMAC)
        XCTAssertEqual(beacon.productID, 0x4FC2)
        XCTAssertEqual(beacon.mac, [0xA4, 0xC1, 0x38, 0x12, 0x34, 0x56])
        XCTAssertEqual(beacon.redactedHex, "1059c24f04xxxxxxxxxxxx")
        XCTAssertNil(MiBeacon.hexBytes("12:34", count: 6))
    }
}

final class BodyCompositionTests: XCTestCase {
    func testMaleExample() {
        // Computed separately from the same equations: 180 cm, 89.8 kg, 491 ohm, 40 years.
        let c = BodyComposition(weight: 89.8, impedance: 491, heightCM: 180, age: 40, male: true)
        XCTAssertEqual(c.bmi, 27.72, accuracy: 0.01)
        XCTAssertEqual(c.leanMass!, 63.24, accuracy: 0.01)
        XCTAssertEqual(c.fatPercent!, 29.58, accuracy: 0.01)
        XCTAssertEqual(c.waterPercent!, 51.93, accuracy: 0.01)
        XCTAssertEqual(c.muscleMass!, 32.55, accuracy: 0.01)
        XCTAssertEqual(c.boneMass!, 3.16, accuracy: 0.01)
    }

    func testFemaleDiffersAndSocksGiveOnlyBMI() {
        let female = BodyComposition(weight: 60, impedance: 600, heightCM: 165, age: 30, male: false)
        XCTAssertEqual(female.fatPercent!, 30.45, accuracy: 0.01)
        let socks = BodyComposition(weight: 60, impedance: nil, heightCM: 165, age: 30, male: false)
        XCTAssertEqual(socks.bmi, 22.04, accuracy: 0.01)
        XCTAssertNil(socks.fatPercent)
    }
}
