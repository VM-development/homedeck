import SwiftUI
import WidgetKit

// Shared by the app and the widgets, so both have the same look.

/// A battery ring for one earbud: green, red at 20% or less, empty when unknown.
struct BatteryRing: View {
    let side: String
    let percent: Int?
    let text: String
    var size: CGFloat = 112

    var body: some View {
        VStack(spacing: size * 0.07) {
            ZStack {
                Circle().stroke(.primary.opacity(0.12), lineWidth: size * 0.09)
                Circle()
                    .trim(from: 0, to: Double(percent ?? 0) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                Text(text)
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(size * 0.15)
            }
            .frame(width: size, height: size)
            Text(side).font(size < 80 ? .caption2.weight(.semibold) : .subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
        .animation(.smooth, value: percent)
    }

    private var color: Color {
        guard let percent else { return .clear }
        return percent <= 20 ? .red : .green
    }
}
