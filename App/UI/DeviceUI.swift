import HubCore
import SwiftUI

/// Devices whose Home tile can switch them on and off.
@MainActor
protocol PowerSwitchable: AnyObject {
    /// Nil until the device has reported.
    var isOn: Bool? { get }
    func setPower(_ on: Bool)
}

/// A device on Home or in Market: its symbol, name and one line of status.
struct DeviceTile: View {
    let symbol: String
    let name: String
    let line: String
    /// Leaves room at the top right for the power button laid over the tile.
    var reservesCorner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(height: 44, alignment: .leading)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(name).font(.headline).lineLimit(2)
            Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.trailing, reservesCorner ? 36 : 0)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(14)
        .contentShape(.rect(cornerRadius: 24))
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

/// The power button in a tile's corner: green when on.
struct TilePowerButton: View {
    let device: any PowerSwitchable

    var body: some View {
        if let on = device.isOn {
            Button(on ? "Turn off" : "Turn on", systemImage: "power") { device.setPower(!on) }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(on ? .green : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .buttonStyle(.plain)
        }
    }
}

/// The top of a device screen: what it is doing, and its main action on the right.
struct DeviceHeader<Action: View>: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tint).frame(minWidth: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            action
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear, in: .rect(cornerRadius: 24))
    }
}

extension DeviceHeader where Action == EmptyView {
    init(symbol: String, title: String, subtitle: String? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A card row whose value opens a menu of choices.
struct MenuRow<Value: Hashable>: View {
    let title: String
    var systemImage: String? = nil
    let options: [Value]
    let label: (Value) -> String
    let selection: Value?
    /// Shown instead of the selection's label, e.g. a countdown.
    var value: String? = nil
    let onSelect: (Value) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { onSelect(option) } label: {
                    if option == selection { Label(label(option), systemImage: "checkmark") } else { Text(label(option)) }
                }
            }
        } label: {
            CardRow(title: title, detail: value ?? selection.map(label) ?? "–", systemImage: systemImage, menu: true)
        }
        .buttonStyle(.plain)
    }
}

/// A small on/off tile for one setting, tinted when on.
struct ToggleTile: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3).accessibilityHidden(true)
                Text(title).font(.footnote.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.glass(isOn ? .clear.tint(selectedTint) : .clear))
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A small tile that does one thing, such as "Return to dock".
struct ActionTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title3).accessibilityHidden(true)
                Text(title).font(.footnote.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.glass(.clear))
        .buttonBorderShape(.roundedRectangle(radius: 18))
    }
}

/// Toggle and action tiles, three to a row.
struct TileRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) { content }
    }
}
