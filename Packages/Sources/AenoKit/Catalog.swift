import Foundation

public enum AenoCatalog {
    /// This device's device.json: what Home and the Market show about it.
    public static let manifest = Bundle.module.url(forResource: "device", withExtension: "json")!
}
