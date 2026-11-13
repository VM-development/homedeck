import WidgetKit
import SwiftUI
import Rex5Kit

@main
struct HomeDeckWidgets: WidgetBundle {
    var body: some Widget {
        Rex5Widget()
        LeftEarbudWidget()
        RightEarbudWidget()
    }
}

// Names and descriptions are literals: building them at runtime in a shared helper made WidgetKit
// hit an assertion and crash the whole extension (crash logs, 2026-11-12).

/// Lock Screen circle for the left earbud's battery.
struct LeftEarbudWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Rex5Left", provider: SnapshotProvider()) { entry in
            EarbudCircle(side: "L", percent: entry.snapshot.leftBattery, snapshot: entry.snapshot)
        }
        .configurationDisplayName("REX5 Left")
        .description("Battery of the left earbud.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// Lock Screen circle for the right earbud's battery.
struct RightEarbudWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Rex5Right", provider: SnapshotProvider()) { entry in
            EarbudCircle(side: "R", percent: entry.snapshot.rightBattery, snapshot: entry.snapshot)
        }
        .configurationDisplayName("REX5 Right")
        .description("Battery of the right earbud.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct EarbudCircle: View {
    let side: String
    let percent: Int?
    let snapshot: EarbudSnapshot

    var body: some View {
        Gauge(value: Double(percent ?? 0), in: 0...100) {
            Text(side)
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text(side).font(.system(size: 10, weight: .bold))
                Text(snapshot.batteryText(percent, inCase: "Case"))
                    .font(.system(size: 13, weight: .semibold))
                    .minimumScaleFactor(0.6)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}
