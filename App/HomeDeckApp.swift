import SwiftUI
import HubCore

@main
struct HomeDeckApp: App {
    enum HomeTab: Hashable { case home, market, settings }

    @State private var store = DeviceStore(kinds: DeviceRegistry.kinds)
    @State private var tab = HomeTab.home
    @State private var homePath: [String] = []

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("Home", systemImage: "house", value: HomeTab.home) {
                    NavigationStack(path: $homePath) {
                        DashboardView(store: store)
                            .navigationDestination(for: String.self) { id in
                                if let kind = store.kind(id: id) {
                                    store.device(for: kind).makeScreen().environment(\.deviceID, id)
                                }
                            }
                    }
                }
                Tab("Market", systemImage: "square.grid.2x2", value: HomeTab.market) {
                    NavigationStack { MarketView(store: store, openDevice: open) }
                }
                Tab("Settings", systemImage: "gearshape", value: HomeTab.settings) {
                    NavigationStack { HubSettingsView(kinds: store.kinds) }
                }
            }
        }
    }

    /// Shows a device's screen on the Home tab.
    private func open(_ kind: DeviceKind) {
        tab = .home
        homePath = [kind.id]
    }
}
