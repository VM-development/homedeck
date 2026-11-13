import SwiftUI
import HubCore

struct MarketView: View {
    let store: DeviceStore
    let openDevice: (DeviceKind) -> Void
    var body: some View { Text("Market") }
}
