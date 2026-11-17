import HubCore
import SwiftUI
import WalkingPadKit

struct WalkingPadScreen: View {
    let pad: WalkingPadDevice
    @State private var confirmForget = false

    var body: some View {
        GlassScreen {
            if pad.status == .notSetUp { setup } else { controls }
        }
        .navigationTitle("WalkingPad C2")
        .toolbar {
            if pad.status != .notSetUp {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Forget this WalkingPad", systemImage: "minus.circle", role: .destructive) { confirmForget = true }
                    }
                }
            }
        }
        .alert("Forget this WalkingPad?", isPresented: $confirmForget) {
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive, action: pad.forget)
        } message: {
            Text("HomeDeck disconnects and searches again next time. Saved walks stay.")
        }
    }

    // MARK: Setup

    private var setup: some View {
        VStack(spacing: 16) {
            GlassCard {
                Text("Switch the WalkingPad on and close KS Fit: the pad talks to one app at a time.")
                    .padding(.vertical, 10)
            }
            BigButton(title: pad.isSearching ? "Searching…" : "Find my WalkingPad", systemImage: "magnifyingglass",
                      tint: .blue, action: pad.search)
                .disabled(pad.isSearching)
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        let live = pad.live
        let online = live != nil
        let running = live?.isRunning == true

        DeviceHeader(symbol: "figure.walk", title: pad.status.cardLine, subtitle: offlineReason) {
            Group {
                if running {
                    RoundButton(title: "Stop", systemImage: "stop.fill", tint: .red, action: pad.stop)
                } else {
                    RoundButton(title: live?.isCountingDown == true ? "Starting" : "Start", systemImage: "play.fill", tint: .green,
                                action: pad.start)
                        .disabled(!online || live?.isCountingDown == true)
                }
            }
            .feature("start-stop")
        }

        GlassCard {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    CardStat(label: "Time", value: live.map { Duration.seconds($0.seconds).formatted(.time(pattern: .minuteSecond)) })
                    CardStat(label: "Distance", value: live.map { "\((Double($0.meters) / 1000).formatted(.number.precision(.fractionLength(2)))) km" })
                    CardStat(label: "Steps", value: live.map { $0.steps.formatted() })
                }
            }
            .padding(.vertical, 10)
            .feature("live-stats")

            let speed = pad.targetSpeed ?? live?.speed ?? 0
            HStack {
                RoundButton(title: "Slower", systemImage: "minus") { pad.setSpeed(speed - 0.5) }
                    .disabled(speed <= WalkingPad.speedRange.lowerBound)
                Spacer()
                Text("\(speed.formatted(.number.precision(.fractionLength(1)))) km/h")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: speed))
                    .animation(.smooth, value: speed)
                Spacer()
                RoundButton(title: "Faster", systemImage: "plus") { pad.setSpeed(speed + 0.5) }
                    .disabled(speed >= WalkingPad.speedRange.upperBound)
            }
            .padding(.vertical, 6)
            .disabled(!running)
            .feature("speed")

            GlassSegments(options: WalkingPad.Mode.allCases, title: \.title,
                          selection: live.flatMap { WalkingPad.Mode(rawValue: $0.mode) }, busy: pad.pendingMode,
                          onSelect: pad.setMode)
                .padding(.vertical, 10)
                .disabled(!online)
                .feature("mode")
        }

        GlassCard(title: "Walks") {
            if pad.walks.isEmpty {
                CardRow(title: "No walks yet")
            }
            ForEach(pad.walks.reversed().prefix(10)) { walk in
                CardRow(title: walk.date.formatted(date: .abbreviated, time: .shortened), detail: walk.summary)
            }
        }
        .feature("history")
        CardCaption("HomeDeck saves a walk when the belt stops while it is connected.")
    }

    private var offlineReason: String? {
        if case .offline(let reason?) = pad.status { return reason }
        return nil
    }
}

private extension WalkingPad.Mode {
    var title: String {
        switch self {
        case .automatic: "Auto"
        case .manual: "Manual"
        case .standby: "Standby"
        }
    }
}

private extension Walk {
    var summary: String {
        let time = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
        let km = (Double(meters) / 1000).formatted(.number.precision(.fractionLength(2)))
        return "\(time) · \(km) km · \(steps.formatted()) steps"
    }
}
