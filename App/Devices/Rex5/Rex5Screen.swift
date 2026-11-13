import SwiftUI
import AVKit
import Rex5Kit

struct Rex5Screen: View {
    enum Screen: Hashable { case devices, tools, settings }

    @Bindable var service: EarbudService
    @Bindable var device: Rex5Device
    @State private var opened: Screen?
    @Namespace private var glass
    @State private var checkedANC: ANCMode?

    private var snapshot: EarbudSnapshot { service.snapshot }

    var body: some View {
        GlassScreen {
            batteryCard.feature("battery")
            noticeCard
            actionButton.feature("connections")
            soundCard
            GlassCard(title: "Paired devices") { DevicesList(service: service) }.feature("connections")
            GlassCard(title: "Tools") { ToolsList(service: service) }.feature("troubleshooting")
            CardCaption("If you swipe HomeDeck away in the app switcher, alerts and widget updates stop until you open it again.")
        }
        .refreshable { await service.refresh() }
        .navigationTitle("REX5")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { opened = .settings } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .navigationDestination(item: $opened) { screen in
            switch screen {
            case .devices: PairedDevicesView(service: service)
            case .tools: ToolsView(service: service)
            case .settings: SettingsView(service: service)
            }
        }
        .sheet(isPresented: Binding(get: { service.needsThisPhoneChoice }, set: { _ in })) {
            NavigationStack { ThisPhonePicker(service: service) }
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $service.showRoutePicker) { RoutePickerSheet() }
        .alert(service.notice ?? "", isPresented: Binding(get: { service.notice != nil }, set: { if !$0 { service.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: device.pendingLink, initial: true) { _, link in
            guard let link else { return }
            device.pendingLink = nil
            switch link {
            case .connect: Task { await service.connectThisPhone() }
            case .disconnect: Task { await service.disconnectThisPhone() }
            case .tools: opened = .tools
            case .devices: opened = .devices
            }
        }
    }
    private var batteryCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack(spacing: 28) {
                    BatteryRing(side: "Left", percent: snapshot.leftBattery, text: snapshot.batteryText(snapshot.leftBattery))
                    BatteryRing(side: "Right", percent: snapshot.rightBattery, text: snapshot.batteryText(snapshot.rightBattery))
                }
                VStack(spacing: 4) {
                    Text(snapshot.statusLine).font(.headline)
                    if !snapshot.otherConnectedNames.isEmpty {
                        Text("Also connected: \(snapshot.otherConnectedNames.joined(separator: ", "))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let readAt = snapshot.batteryReadAt {
                        Text("Battery read \(Text(readAt, style: .relative)) ago").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder private var noticeCard: some View {
        if snapshot.link == .notFound {
            GlassCard {
                NavigationLink { GuidedResetView() } label: {
                    CardRow(title: "Try the guided reset", systemImage: "arrow.counterclockwise", chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
        if snapshot.link == .bluetoothOff {
            GlassCard {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    CardRow(title: "Open Settings", systemImage: "gear", chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var soundCard: some View {
        GlassCard(title: "Sound") {
            GlassSegments(options: ANCMode.allCases, title: \.title, selection: service.ancMode,
                          busy: service.ancPending, checked: checkedANC) { mode in
                Task { await service.setANC(mode) }
            }
            .padding(.vertical, 10)
            .sensoryFeedback(.success, trigger: service.ancConfirmation)
            .task(id: service.ancConfirmation) {
                guard service.ancConfirmation > 0 else { return }
                checkedANC = service.ancMode
                try? await Task.sleep(for: .seconds(1.5))
                checkedANC = nil
            }
            .disabled(snapshot.link != .connected)
            .opacity(snapshot.link == .connected ? 1 : 0.5)
            .feature("noise-control")
            Divider()
            NavigationLink { EqualizerView(service: service) } label: {
                CardRow(title: "Equalizer", detail: service.eqTitle ?? "—", systemImage: "slider.vertical.3", chevron: true)
            }
            .buttonStyle(.plain)
            .feature("equalizer")
        }
    }

    /// Connect and Disconnect share one glass ID, so one morphs into the other when the link changes.
    private var actionButton: some View {
        GlassEffectContainer {
            if snapshot.isConnectedHere {
                capsule("Disconnect this iPhone", tint: .red) { await service.disconnectThisPhone() }
                    .glassEffectID("action", in: glass)
            } else {
                capsule("Connect", tint: .blue) { await service.connectThisPhone() }
                    .glassEffectID("action", in: glass)
            }
        }
        .animation(.smooth(duration: 0.5), value: snapshot.isConnectedHere)
    }

    private func capsule(_ title: String, tint: Color, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            ZStack {
                if service.isWorking { ProgressView().tint(.white) } else { Text(title) }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(service.isWorking)
        .glassEffect(.clear.tint(tint.opacity(0.8)).interactive(), in: .capsule)
    }
}

/// Shown when Connect wasn't confirmed: lets the user pick the earbuds as the audio output.
struct RoutePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassScreen {
            GlassCard {
                VStack(spacing: 16) {
                    Text("The earbuds' sound isn't connected to this iPhone. Put both earbuds in the case, close it for 10 seconds, then take them out. Or open Settings › Bluetooth and tap REX5. If the sound plays elsewhere, tap the button below and choose REX5.")
                        .multilineTextAlignment(.center)
                    RoutePicker().frame(width: 60, height: 60)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.glass(.clear))
                .controlSize(.large)
        }
        .padding(.top, 16)
        .presentationDetents([.medium])
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
