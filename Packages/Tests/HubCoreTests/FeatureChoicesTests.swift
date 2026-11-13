import XCTest
@testable import HubCore

@MainActor
final class FeatureChoicesTests: XCTestCase {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    func testChoicesSurviveRelaunchPerDevice() {
        let defaults = freshDefaults()
        FeatureChoices(defaults: defaults).setHidden(true, "battery", device: "rex5")
        let reloaded = FeatureChoices(defaults: defaults)
        XCTAssertTrue(reloaded.isHidden("battery", device: "rex5"))
        XCTAssertFalse(reloaded.isHidden("battery", device: "fan"))
    }

    func testUnhidingRemovesTheChoice() {
        let choices = FeatureChoices(defaults: freshDefaults())
        choices.setHidden(true, "battery", device: "rex5")
        choices.setHidden(false, "battery", device: "rex5")
        XCTAssertFalse(choices.isHidden("battery", device: "rex5"))
    }

    func testWishlistListsWantedFeaturesThatDontWorkYet() throws {
        let kind = try makeKind(id: "fan", [
            Feature(id: "power", title: "Power", status: .working),
            Feature(id: "timer", title: "Timer", status: .planned),
            Feature(id: "light", title: "Light", status: .notPlanned),
        ])
        let choices = FeatureChoices(defaults: freshDefaults())
        XCTAssertNil(choices.wishlist(for: kind))
        choices.setWanted(true, "light", device: "fan")
        choices.setWanted(true, "timer", device: "fan")
        choices.setWanted(true, "power", device: "fan")  // already working: left out
        XCTAssertEqual(choices.wishlist(for: kind), "HomeDeck wishlist for Test Device:\n- Timer (timer)\n- Light (light)")
    }
}
