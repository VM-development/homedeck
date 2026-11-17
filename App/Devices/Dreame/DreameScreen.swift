import DreameKit
import HubCore
import SwiftUI

struct DreameScreen: View {
    let robot: DreameDevice
    @State private var username = ""
    @State private var password = ""
    @State private var region = "eu"
    @State private var error: String?
    @State private var signingIn = false
    @State private var confirmSignOut = false

    var body: some View {
        GlassScreen {
            if robot.isSetUp { controls } else { setup }
        }
        .navigationTitle("Dreame L40 Ultra")
        .task(id: robot.isSetUp) { if robot.isSetUp { await robot.watch() } }
        .alert("Sign out of Dreamehome?", isPresented: $confirmSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive, action: robot.signOut)
        }
    }

    // MARK: Setup

    @ViewBuilder private var setup: some View {
        GlassCard {
            Text("Dreame robots in the Dreamehome app have no local connection, so HomeDeck goes through Dreame's cloud with your Dreamehome account. If you sign in to Dreamehome with Google or Apple, set a password in the Dreamehome app first.")
                .padding(.vertical, 10)
        }
        GlassCard(title: "Dreamehome account") {
            TextField("E-mail", text: $username)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 10)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .padding(.vertical, 10)
            Picker("Region", selection: $region) {
                ForEach(DreameDevice.regions.keys.sorted(), id: \.self) { Text(DreameDevice.regions[$0]!).tag($0) }
            }
            .padding(.vertical, 6)
        }
        if let error { CardCaption(error).foregroundStyle(.red) }
        BigButton(title: signingIn ? "Signing in…" : "Sign in", systemImage: "person.crop.circle", tint: .blue) {
            signingIn = true
            error = nil
            Task {
                error = await robot.signIn(username: username, password: password, region: region)
                if error == nil { password = "" }
                signingIn = false
            }
        }
        .disabled(signingIn || username.isEmpty || password.isEmpty)
        CardCaption("HomeDeck keeps only the session from Dreame in this iPhone's Keychain, not your password.")
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        GlassCard {
            CardRow(title: robot.status.cardLine, systemImage: robot.values.isEmpty ? "icloud.slash" : "icloud")
            if case .offline(let reason?) = robot.status { CardCaption(reason).padding(.bottom, 8) }
        }

        if robot.int(MIoT(3, 1)) != nil {
            GlassCard(title: "Now") {
                CardRow(title: "State", detail: DreameDevice.stateName(robot.int(MIoT(2, 1))))
                CardRow(title: "Battery", detail: robot.int(MIoT(3, 1)).map { "\($0) %" } ?? "–", systemImage: "battery.75")
                if let error = robot.int(MIoT(2, 2)), error != 0 {
                    CardRow(title: "Error", detail: "code \(error)", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
                CardRow(title: "Last clean", detail: "\(robot.int(MIoT(4, 2)) ?? 0) min · \(robot.int(MIoT(4, 3)) ?? 0) m²")
                if let count = robot.int(MIoT(12, 3)), let area = robot.int(MIoT(12, 4)) {
                    CardRow(title: "All cleans", detail: "\(count) · \(area) m²")
                }
            }
            .feature("status")

            Group {
                if cleaning {
                    BigButton(title: "Pause", systemImage: "pause.fill", tint: .orange) { robot.act(MIoT(2, 2), "pause") }
                } else {
                    BigButton(title: "Start cleaning", systemImage: "play.fill", tint: .green) { robot.act(MIoT(2, 1), "start") }
                }
                GlassCard {
                    Button { robot.act(MIoT(3, 1), "return to dock") } label: { CardRow(title: "Return to dock", systemImage: "house", chevron: true) }
                        .buttonStyle(.plain)
                    Button { robot.act(MIoT(4, 2), "stop") } label: { CardRow(title: "Stop", systemImage: "stop", chevron: true) }
                        .buttonStyle(.plain)
                }
            }
            .feature("start-pause-dock")

            GlassCard(title: "Mode") {
                GlassSegments(options: [2, 0, 3, 1], title: modeTitle, selection: robot.cleaningMode, onSelect: robot.setCleaningMode)
                    .padding(.vertical, 10)
            }
            .feature("clean-mode")

            GlassCard(title: "Suction") {
                GlassSegments(options: [0, 1, 2, 3], title: { ["Quiet", "Standard", "Strong", "Turbo"][$0] },
                              selection: robot.int(MIoT(4, 4))) { robot.set(MIoT(4, 4), $0, "suction") }
                    .padding(.vertical, 10)
            }
            .feature("suction")

            if let wetness = robot.int(MIoT(28, 1)) {
                GlassCard(title: "Mop wetness") {
                    HStack {
                        Slider(value: Binding { draggedWetness ?? Double(wetness) } set: { draggedWetness = $0 }, in: 1...32, step: 1) { editing in
                            guard !editing, let value = draggedWetness else { return }
                            robot.set(MIoT(28, 1), Int(value), "wetness")
                            draggedWetness = nil
                        }
                        Text("\(Int(draggedWetness ?? Double(wetness)))").monospacedDigit().frame(width: 32, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    CardCaption("1 is nearly dry, 32 is wettest.").padding(.bottom, 8)
                }
                .feature("water-level")
            }

            GlassCard(title: "Base station") {
                CardRow(title: "Now", detail: dockState)
                Button { robot.act(MIoT(4, 4), "wash mop pads", in: [(10, "2,1")]) } label: {
                    CardRow(title: "Wash the mop pads", systemImage: "drop", chevron: true)
                }
                .buttonStyle(.plain)
                Button { robot.act(MIoT(4, 4), "dry mop pads", in: [(10, "3,1")]) } label: {
                    CardRow(title: "Dry the mop pads", systemImage: "wind", chevron: true)
                }
                .buttonStyle(.plain)
                Button { robot.act(MIoT(15, 1), "empty dust bin") } label: {
                    CardRow(title: "Empty the dust bin", systemImage: "trash", chevron: true)
                }
                .buttonStyle(.plain)
            }
            .feature("base-station")

            if robot.int(MIoT(5, 1)) != nil {
                GlassCard(title: "Do not disturb") {
                    Toggle("Do not disturb", isOn: Binding { robot.int(MIoT(5, 1)) == 1 } set: { robot.setFlag(MIoT(5, 1), $0, "do not disturb") })
                        .padding(.vertical, 6)
                    DatePicker("From", selection: time(MIoT(5, 2)), displayedComponents: .hourAndMinute).padding(.vertical, 4)
                    DatePicker("Until", selection: time(MIoT(5, 3)), displayedComponents: .hourAndMinute).padding(.vertical, 4)
                }
                .feature("do-not-disturb")
            }

            GlassCard(title: "Parts") {
                ForEach(parts, id: \.name) { part in
                    if let percent = robot.int(part.percent) {
                        CardRow(title: part.name, detail: "\(percent) %\(robot.int(part.hours).map { " · \($0) h left" } ?? "")")
                    }
                }
            }
            .feature("consumables")
        }

        if let problem = robot.problem { CardCaption(problem).foregroundStyle(.red) }
        CardCaption("Goes through Dreame's cloud, so it works away from home too.")

        Button("Sign out of Dreamehome", role: .destructive) { confirmSignOut = true }
            .padding(.top, 8)
    }

    @State private var draggedWetness: Double?

    private var cleaning: Bool { [1, 7, 12, 25, 27, 38].contains(robot.int(MIoT(2, 1)) ?? 0) }

    private func modeTitle(_ raw: Int) -> String {
        switch raw {
        case 2: "Vacuum"
        case 1: "Mop"
        case 0: "Both"
        default: "Then mop"
        }
    }

    private var dockState: String {
        if robot.int(MIoT(15, 5)) == 1 { return "Emptying the dust bin" }
        switch robot.int(MIoT(4, 25)) {
        case 1: return "Washing the mop pads"
        case 2: return "Drying the mop pads"
        case 4: return "Paused"
        case 5: return "Adding water"
        default: return "Idle"
        }
    }

    private let parts: [(name: String, percent: MIoT, hours: MIoT)] = [
        ("Main brush", MIoT(9, 2), MIoT(9, 1)), ("Side brush", MIoT(10, 2), MIoT(10, 1)), ("Filter", MIoT(11, 1), MIoT(11, 2)),
        ("Sensors", MIoT(16, 1), MIoT(16, 2)), ("Wheel", MIoT(30, 2), MIoT(30, 1)),
    ]

    /// "22:00" strings as DatePicker times; written back in the same format.
    private func time(_ prop: MIoT) -> Binding<Date> {
        Binding {
            let parts = (robot.text(prop) ?? "00:00").split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: parts.first ?? 0, minute: parts.dropFirst().first ?? 0, second: 0, of: Date()) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            robot.set(prop, String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0), "do not disturb time")
        }
    }
}
