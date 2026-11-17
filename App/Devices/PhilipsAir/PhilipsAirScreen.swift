import HubCore
import PhilipsAirKit
import SwiftUI

struct PhilipsAirScreen: View {
    let purifier: PhilipsAirDevice
    @State private var ipText = ""
    @State private var error: String?
    @State private var searching = false
    @State private var confirmForget = false

    var body: some View {
        GlassScreen {
            if purifier.isSetUp { controls } else { setup }
        }
        .navigationTitle("Philips 2000i")
        .toolbar {
            if purifier.isSetUp {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Change purifier", systemImage: "arrow.triangle.2.circlepath", role: .destructive) { confirmForget = true }
                    }
                }
            }
        }
        .alert("Remove the purifier's IP?", isPresented: $confirmForget) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: purifier.forget)
        }
    }

    // MARK: Setup

    @ViewBuilder private var setup: some View {
        GlassCard {
            Text("Switch the purifier on. It has to be on this iPhone's Wi-Fi: set it up once in Philips Air+ if it isn't. HomeDeck then talks to it directly, without an account.")
                .padding(.vertical, 10)
        }
        BigButton(title: searching ? "Searching…" : "Find my purifier", systemImage: "magnifyingglass", tint: .blue) {
            searching = true
            error = nil
            Task {
                if let ip = await PurifierFinder.find() {
                    error = purifier.setUp(ip: ip)
                } else {
                    error = "No purifier answered on this Wi-Fi. Check that it's on, that HomeDeck may use the Local Network (Settings > Privacy & Security > Local Network), or enter its IP below."
                }
                searching = false
            }
        }
        .disabled(searching)
        if let error { CardCaption(error).foregroundStyle(.red) }
        GlassCard(title: "Or enter its IP address") {
            HStack {
                TextField("192.168.1.20", text: $ipText)
                    .font(.body.monospaced())
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                Button("Save") { error = purifier.setUp(ip: ipText) }
                    .disabled(ipText.isEmpty)
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        let s = purifier.state
        DeviceHeader(symbol: "humidifier", title: s.map { $0.power ? "On · \(PhilipsAirDevice.modeName($0))" : "Off" } ?? purifier.status.cardLine,
                     subtitle: subtitle) {
            if let s {
                RoundButton(title: s.power ? "Turn off" : "Turn on", systemImage: "power", tint: s.power ? .green : nil) {
                    purifier.setPower(!s.power)
                }
                .feature("power")
            }
        }

        if let s {
            GlassCard {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        CardStat(label: "PM2.5", value: s.pm25.map { "\($0) µg/m³" }).feature("air-quality")
                        CardStat(label: "Allergen index", value: s.allergenIndex.map(String.init)).feature("air-quality")
                    }
                    GridRow {
                        CardStat(label: "Humidity", value: s.humidity.map { "\($0) %" }).feature("humidity-reading")
                        CardStat(label: "Temperature", value: s.temperature.map { "\($0) °C" }).feature("humidity-reading")
                    }
                }
                .padding(.vertical, 10)
            }

            GlassCard {
                MenuRow(title: "Mode", systemImage: "aqi.medium", options: Purifier.modes, label: modeTitle, selection: s.mode) { mode in
                    // Manual needs a speed with it; keep the current one.
                    let pairs: [String: Any] = mode == "M" ? ["mode": "M", "om": manualSpeed(s)] : ["mode": mode]
                    purifier.send(pairs) { $0.mode = mode }
                }
                .feature("mode")
                MenuRow(title: "Fan speed", systemImage: "fan", options: Purifier.fanSpeeds, label: { $0 == "t" ? "Turbo" : "Speed \($0)" },
                        selection: s.mode == "M" ? s.fanSpeed : nil, value: s.mode == "M" ? nil : "Automatic") { speed in
                    purifier.send(["mode": "M", "om": speed]) { $0.mode = "M"; $0.fanSpeed = speed }
                }
                .feature("fan-speed")
                MenuRow(title: "Humidify", systemImage: "humidity", options: [0] + Purifier.humidityTargets,
                        label: { $0 == 0 ? "Off" : $0 == 70 ? "Max" : "To \($0) %" }, selection: s.humidify ? s.humidityTarget : 0) { target in
                    let pairs: [String: Any] = target == 0 ? ["func": "P"] : ["func": "PH", "rhset": target]
                    purifier.send(pairs) { $0.humidify = target != 0; if target != 0 { $0.humidityTarget = target } }
                }
                .feature("humidifier")
                CardRow(title: "Water tank", detail: s.needsWater ? "Empty or out" : "OK", systemImage: "drop")
                    .foregroundStyle(s.needsWater ? .red : .primary)
                    .feature("water-level")
                MenuRow(title: "Timer", systemImage: "timer", options: [0, 1, 2, 4, 8, 12], label: { $0 == 0 ? "Off" : "\($0) h" },
                        selection: s.timer, value: timerLeft(s)) { hours in
                    purifier.send(["dt": hours]) { $0.timer = hours }
                }
                .feature("timer")
                MenuRow(title: "Display light", systemImage: "sun.max", options: Purifier.brightness,
                        label: { $0 == 0 ? "Off" : "\($0) %" }, selection: s.brightness) { level in
                    purifier.send(["aqil": level, "uil": level == 0 ? "0" : "1"]) { $0.brightness = level }
                }
                .feature("light")
                Toggle(isOn: Binding { purifier.state?.childLock ?? false } set: { on in purifier.send(["cl": on]) { $0.childLock = on } }) {
                    Label("Child lock", systemImage: "lock")
                }
                .padding(.vertical, 6)
                .feature("child-lock")
            }

            GlassCard(title: "Filters") {
                CardRow(title: "Pre-filter", detail: s.preFilter.map { $0 == 0 ? "Clean now" : "Clean in \(days($0))" } ?? "–")
                CardRow(title: "HEPA filter", detail: s.hepa.map { $0 == 0 ? "Replace now" : "\(days($0)) left" } ?? "–")
                CardRow(title: "Carbon filter", detail: s.carbon.map { $0 == 0 ? "Replace now" : "\(days($0)) left" } ?? "–")
                CardRow(title: "Humidifier wick", detail: s.wick.map { $0 == 0 ? "Replace now" : "\(days($0)) left" } ?? "–")
            }
            .feature("filter-status")
        }
        if let refused = purifier.refused { CardCaption(refused).foregroundStyle(.red) }
        CardCaption("The purifier answers only on your home Wi-Fi.")
    }

    /// The offline reason, or what the purifier is doing while it's on.
    private var subtitle: String? {
        if case .offline(let reason?) = purifier.status { return reason }
        guard let s = purifier.state, s.power else { return nil }
        return s.humidify ? "Purifying and humidifying" : "Purifying"
    }

    private func timerLeft(_ s: Purifier.State) -> String? {
        guard s.timer > 0, let left = s.timerLeft, left > 0 else { return nil }
        return "\(Duration.seconds(left * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))) left"
    }

    private func modeTitle(_ mode: String) -> String {
        switch mode {
        case "P": "Auto"
        case "A": "Allergen"
        case "S": "Sleep"
        default: "Manual"
        }
    }

    /// While sleeping the purifier reports speed "s", which manual mode doesn't take.
    private func manualSpeed(_ s: Purifier.State) -> String { Purifier.fanSpeeds.contains(s.fanSpeed) ? s.fanSpeed : "1" }

    /// Filter life comes in hours.
    private func days(_ hours: Int) -> String { hours < 48 ? "\(hours) h" : "\(hours / 24) days" }
}
