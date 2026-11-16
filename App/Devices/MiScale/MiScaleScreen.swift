import Charts
import HubCore
import SwiftUI

struct MiScaleScreen: View {
    let scale: MiScaleDevice
    @State private var keyText = ""
    @State private var macText = ""
    @State private var error: String?
    @State private var confirmForget = false

    var body: some View {
        GlassScreen {
            if scale.isSetUp { readings } else { setup }
            listening
        }
        .navigationTitle("Scale S400")
        .task { scale.listen() }
    }

    // MARK: Setup

    @ViewBuilder private var setup: some View {
        GlassCard {
            Text("The scale encrypts each weigh-in. To read it, HomeDeck needs the scale's bind key from your Xiaomi account. On a computer, run Xiaomi Cloud Tokens Extractor, sign in, and copy the S400's \"BLE KEY\".")
                .padding(.vertical, 10)
        }
        GlassCard(title: "Bind key") {
            TextField("32 hex characters", text: $keyText)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 10)
        }
        if scale.knowsMAC {
            CardCaption("MAC address: found in the scale's broadcast.")
        } else {
            GlassCard(title: "MAC address") {
                TextField("AA:BB:CC:DD:EE:FF", text: $macText)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.vertical, 10)
            }
            CardCaption("Or step on the scale: HomeDeck reads the MAC from its broadcast.")
        }
        if let error { CardCaption(error).foregroundStyle(.red) }
        Button {
            error = scale.setUp(key: keyText, mac: macText)
        } label: {
            Text("Save").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52).contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.tint(.blue.opacity(0.7)).interactive(), in: .capsule)
        CardCaption("The key stays in this iPhone's Keychain.")
    }

    // MARK: Readings

    @ViewBuilder private var readings: some View {
        let last = scale.weighIns.last

        GlassCard(title: "Latest") {
            VStack(alignment: .leading, spacing: 4) {
                Text(last.map { "\($0.weight.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "–")
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                if let last {
                    Text("\(last.date.formatted(date: .abbreviated, time: .shortened)) · \(last.profileID == 0 ? "Guest" : "Person \(last.profileID)")")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Step on the scale barefoot.").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
        }
        .feature("weight")

        GlassCard {
            CardRow(title: "Heart rate", detail: last?.heartRate.map { "\($0) bpm" } ?? "–", systemImage: "heart")
        }
        .feature("heart-rate")

        if scale.weighIns.count > 1 {
            GlassCard(title: "Trend") {
                Chart(scale.weighIns.suffix(60)) {
                    LineMark(x: .value("Date", $0.date), y: .value("kg", $0.weight))
                    PointMark(x: .value("Date", $0.date), y: .value("kg", $0.weight))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                .padding(.vertical, 10)
            }
            .feature("history")
        }

        GlassCard(title: "Weigh-ins") {
            if scale.weighIns.isEmpty { CardRow(title: "None yet") }
            ForEach(scale.weighIns.reversed().prefix(30)) { w in
                CardRow(title: w.date.formatted(date: .abbreviated, time: .shortened),
                        detail: "\(w.weight.formatted(.number.precision(.fractionLength(1)))) kg")
            }
        }
        .feature("history")

        if scale.decryptFailed {
            CardCaption("A weigh-in couldn't be decrypted. If the scale was reset or re-added in Xiaomi Home, its bind key changed: enter the new one.")
                .foregroundStyle(.red)
        }
        CardCaption("Close Xiaomi Home before weighing: while it is connected, the scale stops broadcasting. Heart rate needs about 10 seconds barefoot.")

        Button("Change bind key or MAC", role: .destructive) { confirmForget = true }
            .padding(.top, 8)
            .confirmationDialog("Remove the bind key and MAC?", isPresented: $confirmForget) {
                Button("Remove", role: .destructive, action: scale.forget)
            } message: {
                Text("Saved weigh-ins stay.")
            }
    }

    private var listening: some View {
        CardCaption(scale.lastHeard.map { "Heard the scale \($0.formatted(.relative(presentation: .named)))." }
                    ?? "Listening for the scale. It only broadcasts while someone is on it.")
    }
}
