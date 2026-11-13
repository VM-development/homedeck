extension EarbudSnapshot {
    /// The HomeDeck card's status line, for example "L 80% · R In case".
    public var cardSummary: String { "L \(batteryText(leftBattery)) · R \(batteryText(rightBattery))" }
}
