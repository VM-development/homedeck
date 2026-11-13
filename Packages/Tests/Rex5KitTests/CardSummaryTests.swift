import XCTest
@testable import Rex5Kit

final class CardSummaryTests: XCTestCase {
    func testCardSummaryShowsBothEarbuds() {
        var snapshot = EarbudSnapshot(link: .connected, leftBattery: 80, rightBattery: nil, batteryReadAt: Date())
        XCTAssertEqual(snapshot.cardSummary, "L 80% · R In case")
        snapshot.leftBattery = nil
        snapshot.batteryReadAt = nil
        XCTAssertEqual(snapshot.cardSummary, "L — · R —")
    }
}
