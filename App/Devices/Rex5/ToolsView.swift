import SwiftUI

struct ToolsView: View {
    let service: EarbudService

    var body: some View {
        GlassScreen {
            GlassCard { ToolsList(service: service) }
        }
        .navigationTitle("Tools")
    }
}

/// The troubleshooting tools. Used on Home and Tools.
struct ToolsList: View {
    let service: EarbudService

    var body: some View {
        row("Guided reset", "checklist") { GuidedResetView() }
    }

    private func row<Destination: View>(_ title: String, _ icon: String,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) { CardRow(title: title, systemImage: icon, chevron: true) }
            .buttonStyle(.plain)
    }
}

struct GuidedResetView: View {
    static let steps = [
        "Forget the earbuds on this iPhone: Settings › Bluetooth › ⓘ next to the REX5 › Forget This Device.",
        "Remove the earbuds from your other phones, laptops and consoles, or turn their Bluetooth off.",
        "Put both earbuds in the case and press the reset button inside the case until the case light flashes.",
        "Turn Bluetooth off and on again on this iPhone.",
        "Take the earbuds out and check that their LEDs blink alternately (pairing mode).",
        "Pair the earbuds in Settings › Bluetooth, then open REX5 again.",
    ]

    @State private var done: Set<Int> = []

    var body: some View {
        GlassScreen {
            GlassCard {
                ForEach(Self.steps.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    Button {
                        if done.contains(index) { done.remove(index) } else { done.insert(index) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: done.contains(index) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(done.contains(index) ? Color.green : Color.secondary)
                            Text(Self.steps[index]).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            CardCaption("From Noble's TWS troubleshooting steps for the Rex5.")
        }
        .navigationTitle("Guided reset")
    }
}

