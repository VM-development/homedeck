import SwiftUI
import Rex5Kit

struct EqualizerView: View {
    let service: EarbudService
    @State private var gains: [Int] = []
    @State private var applied = false

    private var connected: Bool { service.snapshot.link == .connected }

    var body: some View {
        GlassScreen {
            if service.eqPresets.isEmpty {
                GlassCard {
                    HStack(spacing: 12) {
                        if connected { ProgressView() }
                        Text(connected ? "Reading the earbuds' equalizer…" : "Connect to the earbuds to change the sound.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer {
                        HStack(spacing: 8) {
                            ForEach(service.eqPresets, id: \.self) { preset in
                                GlassChip(title: MusicProcessing.title(of: preset, among: service.eqPresets),
                                          selected: service.eqSelected == preset) {
                                    service.selectEQ(preset)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                    }
                }
                .animation(.smooth, value: service.eqSelected)
                GlassCard {
                    HStack(spacing: 0) {
                        ForEach(gains.indices, id: \.self) { band in
                            BandSlider(value: $gains[band], label: Self.label(service.eqBands[band].frequency),
                                       range: MusicProcessing.gainRange) {
                                service.setEQGains(gains)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                }
                .opacity(service.eqSelected == MusicProcessing.custom ? 1 : 0.6)
                CardCaption("The presets are built into the earbuds, which don't name them. The sliders set Custom; moving one switches to it.")
            }
        }
        .disabled(!connected)
        .navigationTitle("Equalizer")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if service.eqSending {
                    ProgressView()
                } else if applied {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.green)
                }
            }
        }
        .sensoryFeedback(.success, trigger: service.eqConfirmation)
        .task(id: service.eqConfirmation) {
            guard service.eqConfirmation > 0 else { return }
            applied = true
            try? await Task.sleep(for: .seconds(1.5))
            applied = false
        }
        .task {
            gains = service.eqBands.map { Int($0.gain.rounded()) }
            await service.loadEQ()
            gains = service.eqBands.map { Int($0.gain.rounded()) }
        }
    }

    private static func label(_ hertz: Int) -> String {
        guard hertz >= 1000 else { return "\(hertz)" }
        return hertz % 1000 == 0 ? "\(hertz / 1000)k" : String(format: "%.1fk", Double(hertz) / 1000)
    }
}

/// A vertical whole-decibel slider with a clear glass knob; `onCommit` runs when the finger lifts.
struct BandSlider: View {
    @Binding var value: Int
    let label: String
    let range: ClosedRange<Int>
    let onCommit: () -> Void

    private let knob: CGFloat = 22

    var body: some View {
        VStack(spacing: 8) {
            Text(value > 0 ? "+\(value)" : "\(value)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(value == 0 ? .secondary : .primary)
            GeometryReader { geo in
                let travel = geo.size.height - knob
                let steps = CGFloat(range.upperBound - range.lowerBound)
                let y = { (gain: Int) in (1 - CGFloat(gain - range.lowerBound) / steps) * travel + knob / 2 }
                ZStack(alignment: .top) {
                    Capsule().fill(.primary.opacity(0.1)).frame(width: 4, height: geo.size.height)
                    Capsule().fill(.blue.opacity(0.7))
                        .frame(width: 4, height: abs(y(value) - y(0)))
                        .offset(y: min(y(value), y(0)))
                    Circle().fill(.clear)
                        .frame(width: knob, height: knob)
                        .glassEffect(.clear.tint(.blue.opacity(0.35)).interactive(), in: .circle)
                        .offset(y: y(value) - knob / 2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = 1 - (drag.location.y - knob / 2) / travel
                        let gain = Int((CGFloat(range.lowerBound) + fraction * steps).rounded())
                        value = min(max(gain, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in onCommit() })
            }
            .frame(height: 190)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: value)
    }
}
