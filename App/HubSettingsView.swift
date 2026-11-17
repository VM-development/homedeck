import SwiftUI
import HubCore

/// Settings tab: the connection log and the app's version.
struct HubSettingsView: View {
    let kinds: [DeviceKind]

    var body: some View {
        List {
            Section("Log") {
                NavigationLink("Connection log") { LogView(kinds: kinds) }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                Text("HomeDeck controls Bluetooth and Wi-Fi home devices from one app. It's an unofficial hobby project, not affiliated with any device maker.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

/// Every device's exchanges, newest first, filterable by device.
struct LogView: View {
    let kinds: [DeviceKind]
    @State private var log = ConnectionLog.shared
    @State private var device: String?

    var body: some View {
        List(Array(log.entries(for: device).reversed().enumerated()), id: \.offset) { _, entry in
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.date.formatted(date: .abbreviated, time: .standard)) · \(entry.device)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(entry.text).font(.callout.monospaced())
            }
        }
        .navigationTitle("Connection log")
        .toolbar {
            ToolbarItem {
                Picker("Device", selection: $device) {
                    Text("All devices").tag(String?.none)
                    ForEach(kinds) { kind in Text(kind.name).tag(Optional(kind.id)) }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem { ShareLink(item: log.shareText(for: device)) }
        }
    }
}
