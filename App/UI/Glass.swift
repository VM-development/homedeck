import SwiftUI

/// The tint of selected segments and chips.
private let selectedTint = Color.blue.opacity(0.7)

/// A scrolling screen of glass cards on the grouped background.
struct GlassScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

/// Content on a glass card, with an optional small title above it.
struct GlassCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .glassEffect(.clear, in: .rect(cornerRadius: 24))
        }
    }
}

/// A row in a card; a chevron marks rows that open another screen. VoiceOver reads it as one element.
struct CardRow: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.tint).frame(width: 24).accessibilityHidden(true)
            }
            Text(title)
            Spacer(minLength: 8)
            if let detail { Text(detail).foregroundStyle(.secondary) }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A card row that does something when tapped.
struct CardButton: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) { CardRow(title: title, detail: detail, systemImage: systemImage, chevron: true) }
            .buttonStyle(.plain)
    }
}

/// A small label over a big value, for grids of readings.
struct CardStat: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Text(value ?? "–").font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small grey note under the cards, where a list section's footer used to be.
struct CardCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// Segmented control in clear Liquid Glass: a glass track with a tinted glass lens that slides to the selection.
/// `busy` moves the lens at once and shows a spinner until the device confirms.
struct GlassSegments<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    let selection: Value?
    var busy: Value? = nil
    let onSelect: (Value) -> Void
    @Namespace private var lens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    let selected = option == (busy ?? selection)
                    Button { onSelect(option) } label: {
                        HStack(spacing: 6) {
                            if option == busy { ProgressView().controlSize(.small).tint(.white) }
                            Text(title(option))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                Capsule().fill(.clear)
                                    .glassEffect(.clear.tint(selectedTint).interactive(), in: .capsule)
                                    .matchedGeometryEffect(id: "lens", in: lens)
                            }
                        }
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .glassEffect(.clear, in: .capsule)
        }
        // With Reduce Motion the lens jumps instead of sliding.
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: busy ?? selection)
    }
}

/// A clear glass capsule chip, tinted when selected.
struct GlassChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
        }
        .buttonStyle(.glass(selected ? .clear.tint(selectedTint) : .clear))
        .buttonBorderShape(.capsule)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Full-width tinted clear-glass button for a screen's main action. The style dims it when disabled.
struct BigButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass(.clear.tint(tint.opacity(0.7))))
        .buttonBorderShape(.capsule)
    }
}

/// Round clear-glass button with a symbol, for steppers and transport controls. `title` is what VoiceOver reads.
struct RoundButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @ScaledMetric private var size = 48.0

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.glass(.clear))
        .buttonBorderShape(.circle)
    }
}
