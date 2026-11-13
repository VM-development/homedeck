import SwiftUI
import UIKit
import HubCore
import Rex5Kit

/// REX5 behind the HomeDeck contract. EarbudService does the work, as in the standalone app.
@MainActor
@Observable
final class Rex5Device: HomeDevice {
    static let shared = Rex5Device()

    let service = EarbudService.shared
    /// A widget or alert link waiting for Rex5Screen to act on it.
    var pendingLink: DeepLink?

    private init() {
        // REX5 refreshes whenever the app comes to the foreground, as the standalone app did on scenePhase.
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.service.appBecameActive() }
        }
    }

    var status: DeviceStatus {
        let snapshot = service.snapshot
        switch snapshot.link {
        case .connected: return .online(summary: snapshot.cardSummary)
        case .connecting: return .connecting
        default: return .offline(reason: snapshot.statusLine)
        }
    }

    func connect() async { await service.connectThisPhone() }
    func disconnect() async { await service.disconnectThisPhone() }
    func makeScreen() -> AnyView { AnyView(Rex5Screen(service: service, device: self)) }
}
