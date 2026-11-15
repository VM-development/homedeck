import XCTest
import HubCore
import WalkingPadKit
import MiScaleKit
import PhilipsAirKit
import ZeppelinKit
import XiaomiFanKit
import DreameKit
import AenoKit

/// Every device's features.json must decode, with unique ids, before it can reach the Market.
final class CatalogTests: XCTestCase {
    let lists: [String: URL] = [
        "walkingpad-c2": WalkingPadCatalog.featuresURL,
        "mi-scale-s400": MiScaleCatalog.featuresURL,
        "philips-ac2729": PhilipsAirCatalog.featuresURL,
        "zeppelin-pro": ZeppelinCatalog.featuresURL,
        "xiaomi-fan-2-pro": XiaomiFanCatalog.featuresURL,
        "dreame-l40-ultra": DreameCatalog.featuresURL,
        "aeno-ek7s": AenoCatalog.featuresURL,
    ]

    func testEveryFeatureListDecodesWithUniqueIDs() {
        for (device, url) in lists {
            let features = Feature.load(from: url)
            XCTAssertFalse(features.isEmpty, device)
            XCTAssertEqual(Set(features.map(\.id)).count, features.count, "duplicate feature id in \(device)")
        }
    }
}
