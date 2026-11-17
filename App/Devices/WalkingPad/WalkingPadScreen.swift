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

        GlassCard {
            CardRow(title: pad.status.cardLine, systemImage: online ? "dot.radiowaves.left.and.right" : "wifi.slash")
            if case .offline(let reason?) = pad.status { CardCaption(reason).padding(.bottom, 8) }
        }

        GlassCard(title: "Now") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Stat(label: "Speed", value: live.map { "\($0.speed.formatted(.number.precision(.fractionLength(1)))) km/h" })
                    Stat(label: "Time", value: live.map { Duration.seconds($0.seconds).formatted(.time(pattern: .minuteSecond)) })
                }
                GridRow {
                    Stat(label: "Distance", value: live.map { "\((Double($0.meters) / 1000).formatted(.number.precision(.fractionLength(2)))) km" })
                    Stat(label: "Steps", value: live.map { $0.steps.formatted() })
                }
            }
            .padding(.vertical, 10)
        }
        .feature("live-stats")

        Group {
            if live?.isRunning == true {
                BigButton(title: "Stop", systemImage: "stop.fill", tint: .red, action: pad.stop)
            } else {
                BigButton(title: live?.isCountingDown == true ? "Starting…" : "Start", systemImage: "play.fill",
                          tint: .green, action: pad.start)
                    .disabled(!online || live?.isCountingDown == true)
            }
        }
        .feature("start-stop")

        GlassCard(title: "Speed") {
            let speed = pad.targetSpeed ?? live?.speed ?? 0
            HStack {
                RoundButton(systemImage: "minus") { pad.setSpeed(speed - 0.5) }
                    .disabled(speed <= WalkingPad.speedRange.lowerBound)
                Spacer()
                Text("\(speed.formatted(.number.precision(.fractionLength(1)))) km/h")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: speed))
                    .animation(.smooth, value: speed)
                Spacer()
                RoundButton(systemImage: "plus") { pad.setSpeed(speed + 0.5) }
                    .disabled(speed >= WalkingPad.speedRange.upperBound)
            }
            .padding(.vertical, 8)
            .disabled(live?.isRunning != true)
        }
        .feature("speed")

        GlassCard(title: "Mode") {
            GlassSegments(options: WalkingPad.Mode.allCases, title: \.title,
                          selection: live.flatMap { WalkingPad.Mode(rawValue: $0.mode) }, busy: pad.pendingMode,
                          onSelect: pad.setMode)
                .padding(.vertical, 10)
                .disabled(!online)
        }
        .feature("mode")

        GlassCard(title: "Walks") {
            if pad.walks.isEmpty {
                CardRow(title: "No walks yet")
            }
            ForEach(pad.walks.reversed().prefix(30)) { walk in
                CardRow(title: walk.date.formatted(date: .abbreviated, time: .shortened), detail: walk.summary)
            }
        }
        .feature("history")
        CardCaption("HomeDeck saves a walk when the belt stops while it is connected.")

        Button("Forget this WalkingPad", role: .destructive) { confirmForget = true }
            .padding(.top, 8)
            .confirmationDialog("Forget this WalkingPad?", isPresented: $confirmForget) {
                Button("Forget", role: .destructive, action: pad.forget)
            } message: {
                Text("HomeDeck disconnects and searches again next time. Saved walks stay.")
            }
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

private struct Stat: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Text(value ?? "–").font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
