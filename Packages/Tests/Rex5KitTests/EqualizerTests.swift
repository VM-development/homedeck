import XCTest
@testable import Rex5Kit

/// Replies are the Rex5's own answers from 2026-11-12.
final class EqualizerTests: XCTestCase {
    func testANCModePackets() {
        XCTAssertEqual(ANCMode.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertEqual(ANCMode.off.packet.bytes, [0x00, 0x0A, 0x03, 0x14, 0x00])
        XCTAssertEqual(ANCMode.ambient.packet.bytes, [0x00, 0x0A, 0x03, 0x14, 0x02])
    }

    func testMusicProcessingCommands() {
        XCTAssertEqual([MusicProcessing.getPresets, MusicProcessing.setSelected, MusicProcessing.setGains], [0x0A01, 0x0A03, 0x0A06])
        XCTAssertEqual(MusicProcessing.packet(MusicProcessing.setSelected, [63]).bytes, [0x00, 0x1D, 0x0A, 0x03, 0x3F])
    }

    func testParsesTheRex5Presets() {
        let presets = MusicProcessing.presets(from: [0x08, 0x00, 0x01, 0x02, 0x03, 0x06, 0x08, 0x09, 0x3F])
        XCTAssertEqual(presets, [0, 1, 2, 3, 6, 8, 9, 63])
        XCTAssertEqual(presets.map { MusicProcessing.title(of: $0, among: presets) },
                       ["Off", "Preset 1", "Preset 2", "Preset 3", "Preset 4", "Preset 5", "Preset 6", "Custom"])
    }

    func testParsesTheRex5Bands() {
        let reply: [UInt8] = [0x00, 0x04,
                              0x00, 0x78, 0x0B, 0x33, 0x0D, 0x00, 0x00,
                              0x01, 0xF4, 0x0B, 0x33, 0x0D, 0x00, 0x00,
                              0x05, 0xDC, 0x0B, 0x33, 0x0D, 0x00, 0x00,
                              0x13, 0x88, 0x0B, 0x33, 0x0D, 0x00, 0x00,
                              0x2E, 0xE0, 0x0B, 0x33, 0x0D, 0xFF, 0x88]  // last gain changed to -2 dB to test the sign
        let bands = MusicProcessing.bands(from: reply)
        XCTAssertEqual(bands.map(\.frequency), [120, 500, 1500, 5000, 12000])
        XCTAssertEqual(bands.map(\.gain), [0, 0, 0, 0, -2])
        XCTAssertEqual(MusicProcessing.bands(from: [0x00, 0x04, 0x00]), [])  // truncated
    }

    func testGainsAreSixtiethsOfADecibel() {
        let packet = MusicProcessing.gainsPacket([3, -2, 0, 12, -15])
        XCTAssertEqual(packet.vendor, 0x001D)
        XCTAssertEqual(packet.command, 0x0A06)
        XCTAssertEqual(packet.payload, [0x00, 0x04, 0x00, 0xB4, 0xFF, 0x88, 0x00, 0x00, 0x02, 0xD0, 0xFD, 0x30])  // -15 clamps to -12
        XCTAssertEqual(MusicProcessing.gainsPacket([-3], firstBand: 2).payload, [0x02, 0x02, 0xFF, 0x4C])  // one band
    }
}
