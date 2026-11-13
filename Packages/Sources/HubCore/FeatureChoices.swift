import Foundation
import Observation

/// The owner's Show and Want ticks, kept on the phone. What exists and what works lives in features.json.
@MainActor
@Observable
public final class FeatureChoices {
    public static let shared = FeatureChoices()

    private let defaults: UserDefaults
    private var hidden: [String: Set<String>]
    private var wanted: [String: Set<String>]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hidden = Self.load("featureChoices.hidden", from: defaults)
        wanted = Self.load("featureChoices.wanted", from: defaults)
    }

    public func isHidden(_ feature: String, device: String) -> Bool { hidden[device, default: []].contains(feature) }
    public func isWanted(_ feature: String, device: String) -> Bool { wanted[device, default: []].contains(feature) }

    public func setHidden(_ on: Bool, _ feature: String, device: String) {
        Self.set(&hidden, on, feature, device)
        Self.save(hidden, "featureChoices.hidden", to: defaults)
    }

    public func setWanted(_ on: Bool, _ feature: String, device: String) {
        Self.set(&wanted, on, feature, device)
        Self.save(wanted, "featureChoices.wanted", to: defaults)
    }

    /// Plain text for the share sheet, pasted into the device's session. Nil when nothing is wanted.
    public func wishlist(for kind: DeviceKind) -> String? {
        let lines = kind.features
            .filter { $0.status != .working && isWanted($0.id, device: kind.id) }
            .map { "- \($0.title) (\($0.id))" }
        guard !lines.isEmpty else { return nil }
        return (["HomeDeck wishlist for \(kind.name):"] + lines).joined(separator: "\n")
    }

    private static func set(_ table: inout [String: Set<String>], _ on: Bool, _ feature: String, _ device: String) {
        if on { table[device, default: []].insert(feature) } else { table[device, default: []].remove(feature) }
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> [String: Set<String>] {
        (defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]).mapValues(Set.init)
    }

    private static func save(_ table: [String: Set<String>], _ key: String, to defaults: UserDefaults) {
        defaults.set(table.mapValues { Array($0).sorted() }, forKey: key)
    }
}
