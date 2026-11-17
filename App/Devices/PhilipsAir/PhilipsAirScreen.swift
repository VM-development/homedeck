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
        GlassCard {
            CardRow(title: purifier.status.cardLine, systemImage: purifier.state == nil ? "wifi.slash" : "wifi")
            if case .offline(let reason?) = purifier.status { CardCaption(reason).padding(.bottom, 8) }
        }

        if let s = purifier.state {
            GlassCard(title: "Air") {
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

            Group {
                if s.power {
                    BigButton(title: "Turn off", systemImage: "power", tint: .red) { purifier.send(["pwr": "0"]) { $0.power = false } }
                } else {
                    BigButton(title: "Turn on", systemImage: "power", tint: .green) { purifier.send(["pwr": "1"]) { $0.power = true } }
                }
            }
            .feature("power")

            GlassCard(title: "Mode") {
                GlassSegments(options: Purifier.modes, title: modeTitle, selection: s.mode) { mode in
                    // Manual needs a speed with it; keep the current one.
                    let pairs: [String: Any] = mode == "M" ? ["mode": "M", "om": manualSpeed(s)] : ["mode": mode]
                    purifier.send(pairs) { $0.mode = mode }
                }
                .padding(.vertical, 10)
            }
            .feature("mode")

            GlassCard(title: "Fan speed") {
                GlassSegments(options: Purifier.fanSpeeds, title: { $0 == "t" ? "Turbo" : $0 },
                              selection: s.mode == "M" ? s.fanSpeed : nil) { speed in
                    purifier.send(["mode": "M", "om": speed]) { $0.mode = "M"; $0.fanSpeed = speed }
                }
                .padding(.vertical, 10)
                if s.mode != "M" { CardCaption("Choosing a speed switches to manual.").padding(.bottom, 8) }
            }
            .feature("fan-speed")

            GlassCard(title: "Humidifier") {
                GlassSegments(options: [false, true], title: { $0 ? "Purify + humidify" : "Purify only" }, selection: s.humidify) { on in
                    let pairs: [String: Any] = on ? ["func": "PH", "rhset": s.humidityTarget] : ["func": "P"]
                    purifier.send(pairs) { $0.humidify = on }
                }
                .padding(.vertical, 10)
                .feature("humidifier")
                if s.humidify {
                    GlassSegments(options: Purifier.humidityTargets, title: { $0 == 70 ? "Max" : "\($0) %" },
                                  selection: s.humidityTarget) { target in
                        purifier.send(["func": "PH", "rhset": target]) { $0.humidityTarget = target }
                    }
                    .padding(.bottom, 10)
                    .feature("humidity-target")
                }
                CardRow(title: "Water tank", detail: s.needsWater ? "Empty or out" : "OK", systemImage: "drop")
                    .foregroundStyle(s.needsWater ? .red : .primary)
                    .feature("water-level")
            }

            GlassCard(title: "Timer") {
                GlassSegments(options: [0, 1, 2, 4, 8, 12], title: { $0 == 0 ? "Off" : "\($0)h" }, selection: s.timer) { hours in
                    purifier.send(["dt": hours]) { $0.timer = hours }
                }
                .padding(.vertical, 10)
                if s.timer > 0, let left = s.timerLeft, left > 0 {
                    CardCaption("Turns off in \(Duration.seconds(left * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))).")
                        .padding(.bottom, 8)
                }
            }
            .feature("timer")

            GlassCard(title: "Display light") {
                GlassSegments(options: Purifier.brightness, title: { $0 == 0 ? "Off" : "\($0)" }, selection: s.brightness) { level in
                    purifier.send(["aqil": level, "uil": level == 0 ? "0" : "1"]) { $0.brightness = level }
                }
                .padding(.vertical, 10)
            }
            .feature("light")

            GlassCard {
                Toggle(isOn: Binding { purifier.state?.childLock ?? false } set: { on in purifier.send(["cl": on]) { $0.childLock = on } }) {
                    Label("Child lock", systemImage: "lock")
                }
                .padding(.vertical, 6)
            }
            .feature("child-lock")

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

        Button("Change purifier", role: .destructive) { confirmForget = true }
            .padding(.top, 8)
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
