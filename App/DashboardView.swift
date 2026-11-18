import SwiftUI
import HubCore

/// Home tab: added devices as tiles, grouped by category; devices that can switch on and off get a power button on their tile.
struct DashboardView: View {
    let store: DeviceStore

    var body: some View {
        GlassScreen {
            if store.added.isEmpty {
                ContentUnavailableView("No devices yet", systemImage: "square.grid.2x2", description: Text("Add them in Market."))
            }
            ForEach(DeviceKind.byCategory(store.added), id: \.category) { group in
                TileGroup(title: group.category.rawValue) {
                    ForEach(group.kinds) { kind in
                        let device = store.device(for: kind)
                        let power = device as? PowerSwitchable
                        NavigationLink(value: kind.id) {
                            DeviceTile(symbol: kind.symbol, name: kind.name, line: device.status.cardLine, reservesCorner: power != nil)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) {
                            if let power { TilePowerButton(device: power).padding(.trailing, 4) }
                        }
                        .contextMenu {
                            Button("Remove from Home", systemImage: "minus.circle", role: .destructive) { store.remove(kind) }
                        }
                    }
                }
            }
        }
        .navigationTitle("HomeDeck")
    }
}
