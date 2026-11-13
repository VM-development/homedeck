import AppIntents

/// Shortcuts action for an automation like "When REX5 connects → Refresh REX5". iOS doesn't wake an app
/// when headphone audio connects, so this is how the widgets update after the earbuds leave the case.
struct RefreshEarbudsIntent: AppIntent {
    static let title: LocalizedStringResource = "Refresh REX5"
    static let description = IntentDescription("Connects to the earbuds, reads their battery and updates the widgets.")

    @MainActor
    func perform() async throws -> some IntentResult {
        await EarbudService.shared.refreshFromShortcut()
        return .result()
    }
}
