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
        GlassCard {
            CardRow(title: speaker.status.cardLine, systemImage: speaker.volume == nil ? "wifi.slash" : "wifi")
            if case .offline(let reason?) = speaker.status { CardCaption(reason).padding(.bottom, 8) }
        }

        if speaker.volume != nil {
            GlassCard(title: "Now playing") {
                VStack(alignment: .leading, spacing: 4) {
                    if let playing = speaker.nowPlaying {
                        Text(playing.title.isEmpty ? playing.service : playing.title).font(.headline)
                        Text([playing.artist, playing.album].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                        if playing.durationMs > 0 {
                            ProgressView(value: Double(min(playing.elapsedMs, playing.durationMs)), total: Double(playing.durationMs))
                                .padding(.top, 6)
                        }
                        Text(playing.service).font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Nothing playing").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            }
            .feature("now-playing")

            HStack(spacing: 24) {
                RoundButton(systemImage: "backward.fill") { speaker.press(.previous) }
                RoundButton(systemImage: speaker.nowPlaying?.state == 1 ? "pause.fill" : "play.fill") { speaker.press(.playPause) }
                RoundButton(systemImage: "forward.fill") { speaker.press(.next) }
            }
            .disabled(speaker.nowPlaying == nil)
            .frame(maxWidth: .infinity)
            .feature("playback")

            GlassCard(title: "Volume") {
                HStack {
                    Button(action: speaker.toggleMute) {
                        Image(systemName: speaker.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 28)
                    }
                    .buttonStyle(.plain)
                    Slider(value: Binding { draggedVolume ?? Double(speaker.volume ?? 0) } set: { draggedVolume = $0 }, in: 0...100, step: 1) { editing in
                        guard !editing, let value = draggedVolume else { return }
                        speaker.setVolume(Int(value))
                        draggedVolume = nil
                    }
                    Text("\(Int(draggedVolume ?? Double(speaker.volume ?? 0)))").monospacedDigit().frame(width: 36, alignment: .trailing)
                }
                .padding(.vertical, 10)
            }
            .feature("volume")

            GlassCard(title: "Sound") {
                Stepper("Bass \(decibels(speaker.bass))", value: Binding { (speaker.bass ?? 0) / 100 } set: { speaker.setBass($0 * 100) }, in: -6...6)
                    .padding(.vertical, 6)
                Stepper("Treble \(decibels(speaker.treble))", value: Binding { (speaker.treble ?? 0) / 100 } set: { speaker.setTreble($0 * 100) }, in: -6...6)
                    .padding(.vertical, 6)
            }
            .feature("eq")

            if let light = speaker.light {
                GlassCard(title: "Light") {
                    Toggle("Light", isOn: Binding { speaker.light?.enabled ?? false } set: { on in
                        var changed = light
                        changed.enabled = on
                        speaker.setLight(changed)
                    })
                    .padding(.vertical, 6)
                    Slider(value: Binding { draggedBrightness ?? light.brightness } set: { draggedBrightness = $0 }, in: 0.01...1) { editing in
                        guard !editing, let value = draggedBrightness else { return }
                        var changed = light
                        changed.brightness = (value * 100).rounded() / 100
                        speaker.setLight(changed)
                        draggedBrightness = nil
                    }
                    ColorPicker("Colour", selection: Binding { color(light) } set: { speaker.setLight(with($0, light)) }, supportsOpacity: false)
                        .padding(.vertical, 6)
                }
                .feature("light")
                CardCaption("The speaker switches the light off when it goes to standby.").feature("light")
            }

            GlassCard(title: "Auto standby") {
                GlassSegments(options: StreamSDK.autoStandbyChoices, title: { $0 == 0 ? "Never" : "\($0 / 60)m" },
                              selection: speaker.autoStandby, onSelect: speaker.setAutoStandby)
                    .padding(.vertical, 10)
                CardCaption("How long the speaker waits, with nothing playing, before going to standby.").padding(.bottom, 8)
            }
            .feature("power-settings")

            GlassCard(title: "Software") {
                CardRow(title: "Version", detail: speaker.version ?? "–")
                if let update = speaker.update {
                    if update.available {
                        Button { confirmUpdate = true } label: {
                            CardRow(title: "Install \(update.version.isEmpty ? "update" : update.version)", systemImage: "arrow.down.circle", chevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        CardRow(title: "Up to date", systemImage: "checkmark.circle")
                    }
                } else {
                    Button(action: speaker.checkForUpdate) { CardRow(title: "Check for updates", systemImage: "arrow.triangle.2.circlepath", chevron: true) }
                        .buttonStyle(.plain)
                }
            }
            .feature("firmware-update")
        }
        if let problem = speaker.problem { CardCaption(problem).foregroundStyle(.red) }
        CardCaption("The speaker answers only on your home Wi-Fi.")

        Button("Change speaker", role: .destructive) { confirmForget = true }
            .padding(.top, 8)
    }

    private func decibels(_ hundredths: Int?) -> String {
        guard let hundredths else { return "–" }
        let db = hundredths / 100
        return db > 0 ? "+\(db) dB" : "\(db) dB"
    }

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
