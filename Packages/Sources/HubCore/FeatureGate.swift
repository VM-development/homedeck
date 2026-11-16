import SwiftUI

private struct DeviceIDKey: EnvironmentKey { static let defaultValue = "" }

public extension EnvironmentValues {
    /// Set by the shell on each device screen, so `.feature(_:)` knows whose choices to read.
    var deviceID: String {
        get { self[DeviceIDKey.self] }
        set { self[DeviceIDKey.self] = newValue }
    }
}

private struct FeatureGate: ViewModifier {
    let feature: String
    @Environment(\.deviceID) private var device

    @ViewBuilder func body(content: Content) -> some View {
        // Without the shell's .environment(\.deviceID, …) every feature would read as shown, silently.
        let _ = assert(!device.isEmpty, ".feature(\"\(feature)\") used outside a device screen")
        if !FeatureChoices.shared.isHidden(feature, device: device) { content }
    }
}

public extension View {
    /// Hides this part of a device screen when the owner switched the feature off in Market.
    func feature(_ id: String) -> some View { modifier(FeatureGate(feature: id)) }
}
