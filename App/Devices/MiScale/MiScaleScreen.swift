import Charts
import HubCore
import MiScaleKit
import SwiftUI

struct MiScaleScreen: View {
    let scale: MiScaleDevice
    @State private var keyText = ""
    @State private var macText = ""
    @State private var error: String?
    @State private var confirmForget = false
    @State private var editing: Person?
    @State private var shownProfile: Int?

    var body: some View {
        GlassScreen {
            if scale.isSetUp { readings } else { setup }
            listening
        }
        .navigationTitle("Scale S400")
        .task { scale.listen() }
        .sheet(item: $editing) { PersonEditor(person: $0, scale: scale) }
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
        WideButton(title: "Save") { error = scale.setUp(key: keyText, mac: macText) }
        CardCaption("The key stays in this iPhone's Keychain.")
    }

    // MARK: Readings

    @ViewBuilder private var readings: some View {
        let last = scale.weighIns.last
        let profile = shownProfile ?? last?.profileID ?? 1
        let history = scale.weighIns.filter { $0.profileID == profile }

        GlassCard(title: "Latest") {
            VStack(alignment: .leading, spacing: 4) {
                Text(last.map { "\(kg($0.weight)) kg" } ?? "–")
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                if let last {
                    Text("\(last.date.formatted(date: .abbreviated, time: .shortened)) · \(last.profileID == 0 ? "Guest" : scale.person(last.profileID).title)\(last.savedToHealth == true ? " · in Apple Health" : "")")
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

        if let last, last.profileID != 0 {
            GlassCard(title: "Body composition") {
                if let c = scale.composition(for: last) {
                    CardRow(title: "BMI", detail: c.bmi.formatted(.number.precision(.fractionLength(1))))
                    CardRow(title: "Body fat", detail: c.fatPercent.map { "\($0.formatted(.number.precision(.fractionLength(1)))) %" } ?? "–")
                    CardRow(title: "Muscle", detail: c.muscleMass.map { "\(kg($0)) kg" } ?? "–")
                    CardRow(title: "Water", detail: c.waterPercent.map { "\($0.formatted(.number.precision(.fractionLength(1)))) %" } ?? "–")
                    CardRow(title: "Bone", detail: c.boneMass.map { "\(kg($0)) kg" } ?? "–")
                    CardRow(title: "Lean mass", detail: c.leanMass.map { "\(kg($0)) kg" } ?? "–")
                } else {
                    Button { editing = scale.person(last.profileID) } label: {
                        CardRow(title: "Add height, birth year and sex for \(scale.person(last.profileID).title)", chevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .feature("body-composition")
            CardCaption("Estimated from impedance with published equations; Xiaomi Home uses its own formula, so its numbers can differ. Socks block the impedance.")
                .feature("body-composition")
        }

        GlassCard(title: "People on this scale") {
            if scale.profileIDs.isEmpty { CardRow(title: "Appears after the first weigh-in") }
            ForEach(scale.profileIDs, id: \.self) { id in
                let person = scale.person(id)
                Button { editing = person } label: {
                    CardRow(title: person.title, detail: person.savesToHealth ? "Apple Health" : person.details ?? "Add details",
                            systemImage: "person", chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
        .feature("profiles")

        if scale.profileIDs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(scale.profileIDs, id: \.self) { id in
                        GlassChip(title: scale.person(id).title, selected: id == profile) { shownProfile = id }
                    }
                }
            }
            .feature("history")
        }

        if history.count > 1 {
            GlassCard(title: "Trend") {
                Chart(history.suffix(60)) {
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
            if history.isEmpty { CardRow(title: "None yet") }
            ForEach(history.reversed().prefix(30)) { w in
                CardRow(title: w.date.formatted(date: .abbreviated, time: .shortened), detail: "\(kg(w.weight)) kg")
            }
        }
        .feature("history")

        if scale.decryptFailed {
            CardCaption("A weigh-in couldn't be decrypted. If the scale was reset or re-added in Xiaomi Home, its bind key changed: enter the new one.")
                .foregroundStyle(.red)
        }
        CardCaption("Close Xiaomi Home before weighing: while it is connected, the scale stops broadcasting. Heart rate needs about 20 seconds barefoot.")

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

    private func kg(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
}

private struct PersonEditor: View {
    @State var person: Person
    let scale: MiScaleDevice
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $person.name)
                } footer: {
                    Text("The scale recognises people by itself; this is slot \(person.id) in Xiaomi Home.")
                }
                Section("For body composition") {
                    Stepper("Height: \(Int(person.heightCM ?? 170)) cm",
                            value: Binding { person.heightCM ?? 170 } set: { person.heightCM = $0 }, in: 100...220)
                    Stepper("Born: \(String(person.birthYear ?? 1990))",
                            value: Binding { person.birthYear ?? 1990 } set: { person.birthYear = $0 },
                            in: 1920...Calendar.current.component(.year, from: Date()))
                    Picker("Sex", selection: $person.male) {
                        Text("Male").tag(true)
                        Text("Female").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Save to Apple Health", isOn: $person.savesToHealth)
                } footer: {
                    Text("Only this iPhone's owner: weight, BMI, body fat, lean mass and heart rate from each new weigh-in.")
                }
                .feature("apple-health")
            }
            .navigationTitle(person.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            if person.heightCM == nil { person.heightCM = 170 }
                            if person.birthYear == nil { person.birthYear = 1990 }
                            await scale.save(person)
                            dismiss()
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        .environment(\.deviceID, MiScaleDevice.id)
    }
}

/// Full-width tinted glass button.
private struct WideButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52).contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.tint(.blue.opacity(0.7)).interactive(), in: .capsule)
    }
}
