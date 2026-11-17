import HubCore
import SwiftUI
import ZeppelinKit

struct ZeppelinScreen: View {
    let speaker: ZeppelinDevice
    @State private var ipText = ""
    @State private var error: String?
    @State private var searching = false
    @State private var confirmForget = false
    @State private var confirmUpdate = false
    /// Slider values while dragged; sent when the finger lifts.
    @State private var draggedVolume: Double?
    @State private var draggedBrightness: Double?

    var body: some View {
        GlassScreen {
            if speaker.isSetUp { controls } else { setup }
        }
        .navigationTitle("Zeppelin Pro")
        .toolbar {
            if speaker.isSetUp {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Change speaker", systemImage: "arrow.triangle.2.circlepath", role: .destructive) { confirmForget = true }
                    }
                }
            }
        }
        .alert("Forget this speaker?", isPresented: $confirmForget) {
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive, action: speaker.forget)
        }
        .alert("Install the update?", isPresented: $confirmUpdate) {
            Button("Cancel", role: .cancel) {}
            Button("Install", action: speaker.installUpdate)
        } message: {
            Text("The speaker restarts and is silent for a few minutes.")
        }
    }

    // MARK: Setup

    @ViewBuilder private var setup: some View {
        GlassCard {
            Text("The Zeppelin has to be on this iPhone's Wi-Fi (set it up once in the Bowers & Wilkins Music app). HomeDeck then talks to it directly, without an account.")
                .padding(.vertical, 10)
        }
        BigButton(title: searching ? "Searching…" : "Find my Zeppelin", systemImage: "magnifyingglass", tint: .blue) {
            searching = true
            error = nil
            Task {
                if let ip = await ZeppelinDevice.find() {
                    error = speaker.setUp(ip: ip)
                } else {
                    error = "No Zeppelin answered on this Wi-Fi. Check that HomeDeck may use the Local Network (Settings > Privacy & Security > Local Network), or enter its IP below."
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
                Button("Save") { error = speaker.setUp(ip: ipText) }
                    .disabled(ipText.isEmpty)
            }
            .padding(.vertical, 10)
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        let playing = speaker.nowPlaying
        DeviceHeader(symbol: "hifispeaker", title: headerTitle, subtitle: headerSubtitle)
            .feature("now-playing")

        if speaker.volume != nil {
            GlassCard {
                if let playing, playing.durationMs > 0 {
                    ProgressView(value: Double(min(playing.elapsedMs, playing.durationMs)), total: Double(playing.durationMs))
                        .padding(.top, 12)
                        .feature("now-playing")
                }
                HStack(spacing: 28) {
                    RoundButton(title: "Previous track", systemImage: "backward.fill") { speaker.press(.previous) }
                    RoundButton(title: playing?.state == 1 ? "Pause" : "Play", systemImage: playing?.state == 1 ? "pause.fill" : "play.fill",
                                tint: .blue) { speaker.press(.playPause) }
                    RoundButton(title: "Next track", systemImage: "forward.fill") { speaker.press(.next) }
                }
                .disabled(playing == nil)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .feature("playback")
                HStack {
                    Button(speaker.muted ? "Unmute" : "Mute", systemImage: speaker.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           action: speaker.toggleMute)
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .buttonStyle(.plain)
                    Slider(value: Binding { draggedVolume ?? Double(speaker.volume ?? 0) } set: { draggedVolume = $0 }, in: 0...100, step: 1) { editing in
                        guard !editing, let value = draggedVolume else { return }
                        speaker.setVolume(Int(value))
                        draggedVolume = nil
                    }
                    Text("\(Int(draggedVolume ?? Double(speaker.volume ?? 0)))").monospacedDigit().frame(width: 36, alignment: .trailing)
                }
                .padding(.bottom, 6)
                .feature("volume")
            }

            GlassCard {
                MenuRow(title: "Bass", systemImage: "speaker.wave.1", options: Array(-6...6), label: decibels, selection: speaker.bass.map { $0 / 100 }) {
                    speaker.setBass($0 * 100)
                }
                .feature("eq")
                MenuRow(title: "Treble", systemImage: "speaker.wave.3", options: Array(-6...6), label: decibels, selection: speaker.treble.map { $0 / 100 }) {
                    speaker.setTreble($0 * 100)
                }
                .feature("eq")
                MenuRow(title: "Auto standby", systemImage: "moon.zzz", options: StreamSDK.autoStandbyChoices,
                        label: { $0 == 0 ? "Never" : "After \($0 / 60) min" }, selection: speaker.autoStandby, onSelect: speaker.setAutoStandby)
                    .feature("power-settings")
                Group {
                    if let update = speaker.update, update.available {
                        CardButton(title: "Install \(update.version.isEmpty ? "update" : update.version)", systemImage: "arrow.down.circle") { confirmUpdate = true }
                    } else if speaker.update != nil {
                        CardRow(title: "Software", detail: "\(speaker.version ?? "") · up to date", systemImage: "checkmark.circle")
                    } else {
                        CardButton(title: "Software", detail: speaker.version.map { "\($0) · check" } ?? "Check", systemImage: "arrow.triangle.2.circlepath",
                                   action: speaker.checkForUpdate)
                    }
                }
                .feature("firmware-update")
            }

            if let light = speaker.light {
                GlassCard(title: "Light") {
                    HStack {
                        Toggle("Light", isOn: Binding { speaker.light?.enabled ?? false } set: { on in
                            var changed = light
                            changed.enabled = on
                            speaker.setLight(changed)
                        })
                        ColorPicker("Colour", selection: Binding { color(light) } set: { speaker.setLight(with($0, light)) }, supportsOpacity: false)
                            .labelsHidden()
                    }
                    .padding(.vertical, 6)
                    Slider(value: Binding { draggedBrightness ?? light.brightness } set: { draggedBrightness = $0 }, in: 0.01...1) { editing in
                        guard !editing, let value = draggedBrightness else { return }
                        var changed = light
                        changed.brightness = (value * 100).rounded() / 100
                        speaker.setLight(changed)
                        draggedBrightness = nil
                    }
                    .accessibilityLabel("Brightness")
                    .padding(.vertical, 8)
                }
                .feature("light")
                CardCaption("The speaker switches the light off when it goes to standby.").feature("light")
            }
        }
        if let problem = speaker.problem { CardCaption(problem).foregroundStyle(.red) }
        CardCaption("The speaker answers only on your home Wi-Fi.")
    }

    private var headerTitle: String {
        guard speaker.volume != nil else { return speaker.status.cardLine }
        guard let playing = speaker.nowPlaying else { return "Nothing playing" }
        return playing.title.isEmpty ? playing.service : playing.title
    }

    private var headerSubtitle: String? {
        if case .offline(let reason?) = speaker.status { return reason }
        guard let playing = speaker.nowPlaying else { return nil }
        return ([playing.artist] + [playing.service]).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func decibels(_ db: Int) -> String { db > 0 ? "+\(db) dB" : "\(db) dB" }


    private func color(_ light: Stated.Light) -> Color {
        Color(red: Double(light.red) / 255, green: Double(light.green) / 255, blue: Double(light.blue) / 255)
    }

    private func with(_ color: Color, _ light: Stated.Light) -> Stated.Light {
        var (red, green, blue): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: nil)  // sRGB, as the speaker takes it
        var changed = light
        (changed.red, changed.green, changed.blue) = (Int(red * 255), Int(green * 255), Int(blue * 255))
        return changed
    }
}
