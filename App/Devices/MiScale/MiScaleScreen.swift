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
        .toolbar {
            if scale.isSetUp {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Change bind key or MAC", systemImage: "key", role: .destructive) { confirmForget = true }
                    }
                }
            }
        }
        .alert("Remove the bind key and MAC?", isPresented: $confirmForget) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: scale.forget)
        } message: {
            Text("Saved weigh-ins stay.")
        }
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
        BigButton(title: "Save", systemImage: "checkmark", tint: .blue) { error = scale.setUp(key: keyText, mac: macText) }
        CardCaption("The key stays in this iPhone's Keychain.")
    }

    // MARK: Readings

    @ViewBuilder private var readings: some View {
        let last = scale.weighIns.last
        let profile = shownProfile ?? last?.profileID ?? 1
        let history = scale.weighIns.filter { $0.profileID == profile }
        let shownIDs = scale.profileIDs + (scale.weighIns.contains { $0.profileID == 0 } ? [0] : [])
        let composition = last.flatMap { $0.profileID == 0 ? nil : scale.composition(for: $0) }

        DeviceHeader(symbol: "scalemass", title: last.map { "\(kg($0.weight)) kg" } ?? "No weigh-in yet",
                     subtitle: last.map { "\($0.date.formatted(date: .abbreviated, time: .shortened)) · \(name($0.profileID))\($0.savedToHealth == true ? " · in Apple Health" : "")" }
                        ?? "Step on the scale barefoot.")
            .feature("weight")

        if let last {
            GlassCard {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 12) {
                    CardStat(label: "Heart rate", value: last.heartRate.map { "\($0) bpm" }).feature("heart-rate")
                    if let c = composition {
                        Group {
                            CardStat(label: "BMI", value: c.bmi.formatted(.number.precision(.fractionLength(1))))
                            CardStat(label: "Body fat", value: c.fatPercent.map { "\(percent($0)) %" })
                            CardStat(label: "Muscle", value: c.muscleMass.map { "\(kg($0)) kg" })
                            CardStat(label: "Water", value: c.waterPercent.map { "\(percent($0)) %" })
                            CardStat(label: "Bone", value: c.boneMass.map { "\(kg($0)) kg" })
                        }
                        .feature("body-composition")
                    }
                }
                .padding(.vertical, 10)
                if composition == nil, last.profileID != 0 {
                    CardButton(title: "Add height, birth year and sex for body composition") { editing = scale.person(last.profileID) }
                        .feature("body-composition")
                }
            }
            if composition != nil {
                CardCaption("Body composition is estimated from impedance; Xiaomi Home uses its own formula. Socks block the impedance.")
                    .feature("body-composition")
            }
        }

        if shownIDs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(shownIDs, id: \.self) { id in
                        GlassChip(title: name(id), selected: id == profile) { shownProfile = id }
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
                .frame(height: 160)
                .padding(.vertical, 10)
            }
            .feature("history")
        }

        GlassCard(title: "Weigh-ins") {
            if history.isEmpty { CardRow(title: "None yet") }
            ForEach(history.reversed().prefix(10)) { w in
                Menu {
                    Section("Move to") {
                        ForEach(scale.profileIDs + [0], id: \.self) { id in
                            if id != w.profileID { Button(name(id)) { scale.move(w, to: id) } }
                        }
                    }
                } label: {
                    CardRow(title: w.date.formatted(date: .abbreviated, time: .shortened), detail: "\(kg(w.weight)) kg")
                }
                .buttonStyle(.plain)
            }
        }
        .feature("history")
        CardCaption("Tap a weigh-in to move it to someone else.").feature("profiles")

        GlassCard(title: "People") {
            ForEach(scale.profileIDs, id: \.self) { id in
                let person = scale.person(id)
                CardButton(title: person.title, detail: person.savesToHealth ? "Apple Health" : person.details ?? "Add details",
                           systemImage: "person") { editing = person }
            }
            CardButton(title: "Add person", systemImage: "plus") { editing = Person(id: scale.nextPersonID) }
        }
        .feature("profiles")

        if scale.decryptFailed {
            CardCaption("A weigh-in couldn't be decrypted. If the scale was reset or re-added in Xiaomi Home, its bind key changed: enter the new one.")
                .foregroundStyle(.red)
        }
        CardCaption("Close Xiaomi Home before weighing: while it is connected, the scale stops broadcasting. Heart rate needs about 20 seconds barefoot.")
    }

    private var listening: some View {
        CardCaption(scale.lastHeard.map { "Heard the scale \($0.formatted(.relative(presentation: .named)))." }
                    ?? "Listening for the scale. It only broadcasts while someone is on it.")
    }

    private func name(_ id: Int) -> String { id == 0 ? "Guest" : scale.person(id).title }

    private func kg(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }

    private func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
}

private struct PersonEditor: View {
    @State var person: Person
    let scale: MiScaleDevice
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $person.name)
                } footer: {
                    Text("The scale numbers people itself: weigh-ins it marks as person \(person.id) land here.")
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
                if scale.people.contains(where: { $0.id == person.id }) {
                    Section {
                        Button("Remove \(person.title)", role: .destructive) { confirmRemove = true }
                    } footer: {
                        Text("Their weigh-ins move to Guest.")
                    }
                }
            }
            .alert("Remove \(person.title)?", isPresented: $confirmRemove) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    scale.remove(person.id)
                    dismiss()
                }
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
