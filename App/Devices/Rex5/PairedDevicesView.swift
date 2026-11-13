import SwiftUI
import Rex5Kit

struct PairedDevicesView: View {
    let service: EarbudService

    var body: some View {
        GlassScreen {
            GlassCard { DevicesList(service: service) }
            CardCaption("The earbuds update this list themselves when a device connects or disconnects.")
        }
        .navigationTitle("Paired devices")
        .refreshable { await service.refresh() }
    }
}

/// The earbuds' paired devices, with Disconnect for the other connected ones. Used on Home and Paired devices.
struct DevicesList: View {
    let service: EarbudService

    var body: some View {
        let devices = service.snapshot.devices
        if devices.isEmpty {
            Label("Connect to the earbuds to see their paired devices.", systemImage: "earbuds")
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
        }
        ForEach(Array(devices.enumerated()), id: \.element.name) { index, device in
            if index > 0 { Divider() }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                    Text(caption(for: device)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if device.isConnected && device.name != service.snapshot.thisPhoneName {
                    Button("Disconnect") { Task { await service.disconnect(device) } }
                        .buttonStyle(.glass(.clear))
                        .disabled(service.isWorking || service.snapshot.link != .connected)
                }
            }
            .padding(.vertical, 10)
        }
    }

    private func caption(for device: PairedDevice) -> String {
        let state = device.isConnected ? "Connected" : "Not connected"
        return device.name == service.snapshot.thisPhoneName ? "This iPhone · \(state)" : state
    }
}
