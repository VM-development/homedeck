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
        GlassCard {
            CardRow(title: fan.status.cardLine, systemImage: fan.state == nil ? "wifi.slash" : "wifi")
            if case .offline(let reason?) = fan.status { CardCaption(reason).padding(.bottom, 8) }
        }

        if let s = fan.state {
            Group {
                if s.power {
                    BigButton(title: "Turn off", systemImage: "power", tint: .red) { fan.set(.power, false) { $0.power = false } }
                } else {
                    BigButton(title: "Turn on", systemImage: "power", tint: .green) { fan.set(.power, true) { $0.power = true } }
                }
            }
            .feature("power")

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
                .padding(.vertical, 10)
            }
            .feature("speed")

            GlassCard(title: "Mode") {
                GlassSegments(options: [false, true], title: { $0 ? "Natural breeze" : "Direct" }, selection: s.natural) { natural in
                    fan.set(.mode, natural ? 1 : 0) { $0.natural = natural }
                }
                .padding(.vertical, 10)
            }
            .feature("mode")

            GlassCard(title: "Oscillation") {
                Toggle("Oscillate", isOn: toggle(.swing, \.swing))
                    .padding(.vertical, 6)
                GlassSegments(options: Fan.angles, title: { "\($0)°" }, selection: s.angle) { angle in
                    fan.set(.angle, angle) { $0.angle = angle }
                }
                .padding(.bottom, 10)
            }
            .feature("oscillation")

            GlassCard(title: "Timer") {
                GlassSegments(options: [0, 30, 60, 120, 240, 480], title: timerTitle, selection: s.timer == 0 ? 0 : nil) { minutes in
                    fan.set(.timer, minutes) { $0.timer = minutes }
                }
                .padding(.vertical, 10)
                if s.timer > 0 {
                    CardCaption("Turns off in \(Duration.seconds(s.timer * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))).")
                        .padding(.bottom, 8)
                }
            }
            .feature("timer")

            GlassCard {
                Toggle(isOn: toggle(.lock, \.lock)) {
                    Label("Child lock", systemImage: "lock")
                }
                .padding(.vertical, 6)
                .feature("child-lock")
                Toggle(isOn: toggle(.light, \.light)) {
                    Label("Indicator light", systemImage: "lightbulb")
                }
                .padding(.vertical, 6)
                .feature("light")
                Toggle(isOn: toggle(.sound, \.sound)) {
                    Label("Beep", systemImage: "speaker.wave.2")
                }
                .padding(.vertical, 6)
                .feature("sound")
            }

            if s.fault != 0 { CardCaption("The fan reports motor fault \(s.fault).").foregroundStyle(.red) }
        }
        if let refused = fan.refused { CardCaption(refused).foregroundStyle(.red) }
        CardCaption("The fan answers only on your home Wi-Fi.")

        Button("Change token or IP", role: .destructive) { confirmForget = true }
            .padding(.top, 8)
    }

    /// Bindings read the fan's live state: a copy captured when the body ran would show the old value
    /// for a moment after each change.
    private var shownSpeed: Double { dragged ?? Double(fan.state?.speed ?? 1) }

    private func toggle(_ property: Fan.Property, _ key: WritableKeyPath<Fan.State, Bool>) -> Binding<Bool> {
        Binding { fan.state?[keyPath: key] ?? false } set: { on in fan.set(property, on) { $0[keyPath: key] = on } }
    }

    private func timerTitle(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Off"
        case 30: "30m"
        default: "\(minutes / 60)h"
        }
    }
}
