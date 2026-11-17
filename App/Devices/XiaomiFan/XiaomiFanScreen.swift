import HubCore
import SwiftUI
import XiaomiFanKit

struct XiaomiFanScreen: View {
    let fan: XiaomiFanDevice
    @State private var tokenText = ""
    @State private var ipText = ""
    @State private var error: String?
    @State private var confirmForget = false
    /// The slider's value while it is dragged; written when the finger lifts.
    @State private var dragged: Double?

    var body: some View {
        GlassScreen {
            if fan.isSetUp { controls } else { setup }
        }
        .navigationTitle("Fan 2 Pro")
        .task(id: fan.isSetUp) { if fan.isSetUp { await fan.watch() } }
        .toolbar {
            if fan.isSetUp {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Change token or IP", systemImage: "key", role: .destructive) { confirmForget = true }
                    }
                }
            }
        }
        .alert("Remove the token and IP?", isPresented: $confirmForget) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: fan.forget)
        }
    }

    // MARK: Setup

    @ViewBuilder private var setup: some View {
        GlassCard {
            Text("HomeDeck talks to the fan over your Wi-Fi, encrypted with the fan's token. In the Xiaomi Cloud Tokens Extractor output, find the fan and copy its TOKEN and IP.")
                .padding(.vertical, 10)
        }
        GlassCard(title: "Token") {
            TextField("32 hex characters", text: $tokenText)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 10)
        }
        GlassCard(title: "IP address") {
            TextField("192.168.1.20", text: $ipText)
                .font(.body.monospaced())
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .padding(.vertical, 10)
        }
        if let error { CardCaption(error).foregroundStyle(.red) }
        BigButton(title: "Save", systemImage: "checkmark", tint: .blue) { error = fan.setUp(token: tokenText, ip: ipText) }
        CardCaption("The token stays in this iPhone's Keychain. If the router gives the fan a new IP, enter it again; reserving the IP in the router avoids that.")
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        let s = fan.state
        DeviceHeader(symbol: "fan.floor", title: s.map { $0.power ? "On · speed \($0.level)" : "Off" } ?? fan.status.cardLine,
                     subtitle: subtitle) {
            if let s {
                RoundButton(title: s.power ? "Turn off" : "Turn on", systemImage: "power", tint: s.power ? .green : nil) {
                    fan.setPower(!s.power)
                }
                .feature("power")
            }
        }

        if let s {
            GlassCard(title: "Speed") {
                GlassSegments(options: Fan.levels, title: { "\($0)" }, selection: s.level) { level in
                    fan.set(.level, level) { $0.level = level }
                }
                .padding(.top, 10)
                HStack {
                    Slider(value: Binding { shownSpeed } set: { dragged = $0 }, in: 1...100, step: 1) { editing in
                        guard !editing, let value = dragged else { return }
                        fan.set(.speed, Int(value)) { $0.speed = Int(value) }
                        dragged = nil
                    }
                    Text("\(Int(shownSpeed)) %").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                .padding(.vertical, 8)
            }
            .feature("speed")

            GlassCard {
                MenuRow(title: "Mode", systemImage: "wind", options: [false, true], label: { $0 ? "Natural breeze" : "Direct" },
                        selection: s.natural) { natural in
                    fan.set(.mode, natural ? 1 : 0) { $0.natural = natural }
                }
                .feature("mode")
                MenuRow(title: "Oscillate", systemImage: "arrow.left.and.right", options: [0] + Fan.angles,
                        label: { $0 == 0 ? "Off" : "\($0)°" }, selection: s.swing ? s.angle : 0, onSelect: oscillate)
                    .feature("oscillation")
                MenuRow(title: "Timer", systemImage: "timer", options: [0, 30, 60, 120, 240, 480], label: timerTitle,
                        selection: s.timer == 0 ? 0 : nil, value: s.timer > 0 ? "\(left(s.timer)) left" : nil) { minutes in
                    fan.set(.timer, minutes) { $0.timer = minutes }
                }
                .feature("timer")
            }

            TileRow {
                ToggleTile(title: "Child lock", systemImage: "lock", isOn: s.lock) { flip(.lock, \.lock) }.feature("child-lock")
                ToggleTile(title: "Light", systemImage: "lightbulb", isOn: s.light) { flip(.light, \.light) }.feature("light")
                ToggleTile(title: "Beep", systemImage: "speaker.wave.2", isOn: s.sound) { flip(.sound, \.sound) }.feature("sound")
            }

            if s.fault != 0 { CardCaption("The fan reports motor fault \(s.fault).").foregroundStyle(.red) }
        }
        if let refused = fan.refused { CardCaption(refused).foregroundStyle(.red) }
        CardCaption("The fan answers only on your home Wi-Fi.")
    }

    /// The offline reason, or what the fan is doing while it's on.
    private var subtitle: String? {
        if case .offline(let reason?) = fan.status { return reason }
        guard let s = fan.state, s.power else { return nil }
        return [s.natural ? "Natural breeze" : "Direct", s.swing ? "oscillating \(s.angle)°" : nil].compactMap { $0 }.joined(separator: " · ")
    }

    /// Off stops oscillating; an angle also starts it.
    private func oscillate(_ angle: Int) {
        guard angle != 0 else { return fan.set(.swing, false) { $0.swing = false } }
        if fan.state?.swing != true { fan.set(.swing, true) { $0.swing = true } }
        fan.set(.angle, angle) { $0.angle = angle }
    }

    /// Reads the live state, so quick taps don't act on a value from before the last change.
    private func flip(_ property: Fan.Property, _ key: WritableKeyPath<Fan.State, Bool>) {
        let on = !(fan.state?[keyPath: key] ?? false)
        fan.set(property, on) { $0[keyPath: key] = on }
    }

    /// The slider's value: while dragging, the finger's; otherwise the fan's live speed.
    private var shownSpeed: Double { dragged ?? Double(fan.state?.speed ?? 1) }

    private func left(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func timerTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Off"
        case 30: "30 min"
        default: "\(minutes / 60) h"
        }
    }
}
