import SwiftUI
import HubCore

/// Market tab: every device HomeDeck knows, with how much of it works.
struct MarketView: View {
    let store: DeviceStore
    let openDevice: (DeviceKind) -> Void

    var body: some View {
        GlassScreen {
            ForEach(store.kinds) { kind in
                NavigationLink {
                    FeatureListView(kind: kind, store: store, openDevice: openDevice)
                } label: {
                    MarketTile(kind: kind, isAdded: store.isAdded(kind))
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Market")
    }
}

struct MarketTile: View {
    let kind: DeviceKind
    let isAdded: Bool

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol).font(.title2).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.name).font(.headline)
                    Text("\(kind.link == .bluetooth ? "Bluetooth" : "Wi-Fi") · \(kind.workingSummary)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if isAdded { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
    }
}

/// A device's features: Show toggles for what works, Want toggles for the rest, and the wishlist.
struct FeatureListView: View {
    let kind: DeviceKind
    let store: DeviceStore
    let openDevice: (DeviceKind) -> Void
    @State private var choices = FeatureChoices.shared

    private func features(_ status: Feature.Status) -> [Feature] { kind.features.filter { $0.status == status } }

    var body: some View {
        List {
            section("Working", footer: "Switch off to hide it from the device screen.", features(.working)) { feature in
                Binding(get: { !choices.isHidden(feature.id, device: kind.id) },
                        set: { choices.setHidden(!$0, feature.id, device: kind.id) })
            }
            section("Planned", footer: "Switch on to ask for it in the wishlist.", features(.planned), want)
            // In the list, not a bottom toolbar: iOS hides bottom toolbars when there is a tab bar.
            if let text = choices.wishlist(for: kind) {
                Section { ShareLink("Send wishlist", item: text) }
            }
        }
        .navigationTitle(kind.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.isAdded(kind) {
                    Button("Open") { openDevice(kind) }
                } else {
                    Button("Add") {
                        store.add(kind)
                        openDevice(kind)
                    }
                }
            }
        }
    }

    private func want(_ feature: Feature) -> Binding<Bool> {
        Binding(get: { choices.isWanted(feature.id, device: kind.id) },
                set: { choices.setWanted($0, feature.id, device: kind.id) })
    }

    @ViewBuilder
    private func section(_ title: String, footer: String, _ features: [Feature],
                         _ binding: @escaping (Feature) -> Binding<Bool>) -> some View {
        if !features.isEmpty {
            Section {
                ForEach(features) { feature in Toggle(feature.title, isOn: binding(feature)) }
            } header: {
                Text(title)
            } footer: {
                Text(footer)
            }
        }
    }
}
