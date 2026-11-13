import SwiftUI

struct SettingsView: View {
    let service: EarbudService

    var body: some View {
        GlassScreen {
            GlassCard(title: "This iPhone") {
                CardRow(title: "Entry", detail: service.snapshot.thisPhoneName ?? "Not chosen")
                Divider()
                NavigationLink { ThisPhonePicker(service: service) } label: { CardRow(title: "Change", chevron: true) }
                    .buttonStyle(.plain)
                    .disabled(service.snapshot.devices.isEmpty)
            }
            GlassCard(title: "Earbuds") {
                CardRow(title: "Firmware", detail: service.snapshot.firmware ?? "Unknown")
            }
        }
        .navigationTitle("Settings")
    }
}

/// Lets the user say which entry in the earbuds' list is this iPhone; iOS doesn't tell apps the phone's Bluetooth name.
struct ThisPhonePicker: View {
    let service: EarbudService
    @State private var choice = ""
    @Environment(\.dismiss) private var dismiss

    private var names: [String] { service.snapshot.devices.map(\.name) }

    var body: some View {
        GlassScreen {
            GlassCard {
                ForEach(Array(names.enumerated()), id: \.element) { index, name in
                    if index > 0 { Divider() }
                    Button { choice = name } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            if choice == name { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint) }
                        }
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            CardCaption("iOS doesn't tell apps this iPhone's Bluetooth name, so pick it from the earbuds' list.")
        }
        .navigationTitle("Which one is this iPhone?")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    service.setThisPhone(choice)
                    dismiss()
                }
                .disabled(choice.isEmpty)
            }
        }
        .onAppear {
            choice = service.snapshot.thisPhoneName ?? service.suggestedThisPhone ?? names.first ?? ""
        }
    }
}
