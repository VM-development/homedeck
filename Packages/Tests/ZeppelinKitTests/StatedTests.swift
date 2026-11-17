import XCTest
@testable import ZeppelinKit

/// Message shapes as the owner's speaker sent them (2026-11-17), with made-up ids, titles and values.
final class StatedTests: XCTestCase {
    let node = "11111111-2222-3333-4444-555555555555"

    func push(_ name: String, _ parameters: String, from sender: String? = nil) -> Data {
        Data("""
        {"type":"message","payload":{"signature":"x","args":{"message":{"type":"query","method":{"name":"\(name)","parameters":\(parameters)}},
        "sendingNodeID":"\(sender ?? node)","messageID":"m","replyID":"r","channel":"c","serviceID":"s"}}}
        """.utf8)
    }

    func testVolumePush() {
        XCTAssertEqual(Stated.events(inPush: push("volume_changed", #"{"muted":false,"value":30}"#), node: node), [.volume(30)])
        XCTAssertEqual(Stated.events(inPush: push("success", #"{"muted":false,"source":"","value":36}"#), node: node), [.volumeReply(36)])
        XCTAssertEqual(Stated.events(inPush: push("volume_changed", #"{"muted":false,"value":30}"#, from: "other"), node: node), [],
                       "another mesh member's message is ignored")
    }

    func testPropertiesInRepliesAndPushes() {
        XCTAssertEqual(Stated.events(inReply: Data(#"{"property":"liberty.property.gain.bass","value":200}"#.utf8), node: node), [.bass(200)])
        XCTAssertEqual(Stated.events(inPush: push("property_changed", #"{"property":"liberty.property.gain.treble","value":-100}"#), node: node),
                       [.treble(-100)])
        let light = #"{"property":"liberty.lights.hardware-downlight","value":{"enabled":true,"supported":true,"rgb":{"red":0,"blue":255,"green":0},"brightness":0.21}}"#
        XCTAssertEqual(Stated.events(inReply: Data(light.utf8), node: node),
                       [.light(.init(enabled: true, brightness: 0.21, red: 0, green: 0, blue: 255))])
        XCTAssertEqual(Stated.events(inReply: Data(#"{"update_release_notes":"","update_version":"","update_available":false}"#.utf8), node: node),
                       [.update(available: false, version: "")])
    }

    func testNowPlaying() throws {
        let tile = """
        {"property":"liberty.oobed.audiotile","value":{"\(node)+audiod_plugin_airplay2":{"title":"Song","artist":"Band","album":"Record",
        "serviceName":"AirPlay","state":1,"duration":250853,"elapsedTime":6900,"enabledPlaybackActions":["previous_track","next_track","play"],
        "sinkNodeIDs":["\(node)"],"tileID":"\(node)+audiod_plugin_airplay2","serviceID":"audiod_plugin_airplay2"}}}
        """
        guard case .nowPlaying(let playing?) = Stated.events(inPush: push("property_changed", tile), node: node).first else {
            return XCTFail("no now-playing event")
        }
        XCTAssertEqual(playing.title, "Song")
        XCTAssertEqual(playing.service, "AirPlay")
        XCTAssertEqual(playing.elapsedMs, 6900)
        XCTAssertEqual(Stated.events(inPush: push("property_changed", #"{"property":"liberty.oobed.audiotile","value":{}}"#), node: node),
                       [.nowPlaying(nil)])
    }

    func testRequests() throws {
        let volume = try XCTUnwrap(JSONSerialization.jsonObject(with: Stated.setVolume(140, muted: false)) as? [String: Any])
        let parameters = try XCTUnwrap((volume["method"] as? [String: Any])?["parameters"] as? [String: Any])
        XCTAssertEqual(volume["type"] as? String, "query")
        XCTAssertEqual(parameters["value"] as? Int, 100, "clamped")
        XCTAssertEqual(StreamSDK.setURL(ip: "10.0.0.2", path: StreamSDK.autoStandby, int: 600).absoluteString,
                       "http://10.0.0.2/api/setData?path=settings:/system/maxIdleTime&role=value&value=%7B%22type%22:%22i32_%22,%22i32_%22:600%7D")
        XCTAssertEqual(StreamSDK.int(Data(#"{"type":"i32_","i32_":1200}"#.utf8)), 1200)
        XCTAssertEqual(StreamSDK.int(Data(#"[{"type":"i32_","i32_":0}]"#.utf8)), 0)
    }
}
