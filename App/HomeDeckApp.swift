import SwiftUI
import UserNotifications
import HubCore
import Rex5Kit

/// Routes notification taps (REX5 takeover alerts) to a deep link.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var openLink: ((DeepLink) -> Void)?
    var pendingLink: DeepLink?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let text = response.notification.request.content.userInfo["link"] as? String,
           let url = URL(string: text), let link = DeepLink(url: url) {
            if let openLink { openLink(link) } else { pendingLink = link }
        }
        completionHandler()
    }
}

@main
struct HomeDeckApp: App {
    enum HomeTab: Hashable { case home, market, settings }

    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
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
            .onOpenURL { url in
                if let link = DeepLink(url: url) { openRex5(link) }
            }
            .onAppear {
                delegate.openLink = { openRex5($0) }
                if let pending = delegate.pendingLink {
                    openRex5(pending)
                    delegate.pendingLink = nil
                }
            }
        }
    }

    /// Shows a device's screen on the Home tab.
    private func open(_ kind: DeviceKind) {
        tab = .home
        homePath = [kind.id]
    }

    /// Widgets and REX5 alerts link to rex5:// URLs. They open the REX5 screen, which acts on the link.
    private func openRex5(_ link: DeepLink) {
        guard let kind = store.kind(id: "rex5") else { return }
        Rex5Device.shared.pendingLink = link
        open(kind)
    }
}
