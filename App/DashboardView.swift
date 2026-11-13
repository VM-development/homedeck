import SwiftUI
import HubCore

/// Home tab: one glass card per added device.
struct DashboardView: View {
    let store: DeviceStore

    var body: some View {
        GlassScreen {
            if store.added.isEmpty {
                CardCaption("No devices yet. Add them in Market.")
            }
            ForEach(store.added) { kind in
                NavigationLink(value: kind.id) { DeviceCard(kind: kind, device: store.device(for: kind)) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Home", systemImage: "minus.circle", role: .destructive) { store.remove(kind) }
                    }
            }
        }
        .navigationTitle("HomeDeck")
    }
}

struct DeviceCard: View {
    let kind: DeviceKind
    let device: any HomeDevice

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol).font(.title2).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.name).font(.headline)
                    Text(device.status.cardLine).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
    }
}
