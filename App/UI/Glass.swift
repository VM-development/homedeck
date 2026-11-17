import SwiftUI

/// A scrolling screen of glass cards over the gradient.
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

/// A row in a card; a chevron marks rows that open another screen.
struct CardRow: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.tint).frame(width: 24)
            }
            Text(title)
            Spacer(minLength: 8)
            if let detail { Text(detail).foregroundStyle(.secondary) }
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
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
/// `busy` moves the lens at once and shows a spinner until confirmed; `checked` shows a checkmark.
struct GlassSegments<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    let selection: Value?
    var busy: Value? = nil
    var checked: Value? = nil
    let onSelect: (Value) -> Void
    @Namespace private var lens

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                ForEach(options, id: \.self) { option in
                    let selected = option == (busy ?? selection)
                    Button { onSelect(option) } label: {
                        HStack(spacing: 6) {
                            if option == busy {
                                ProgressView().controlSize(.small).tint(.white)
                            } else if option == checked {
                                Image(systemName: "checkmark").font(.caption.weight(.bold))
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Text(title(option))
                        }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .white : .primary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background {
                                if selected {
                                    Capsule().fill(.clear)
                                        .glassEffect(.clear.tint(.blue.opacity(0.7)).interactive(), in: .capsule)
                                        .matchedGeometryEffect(id: "lens", in: lens)
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassEffect(.clear, in: .capsule)
        }
        .animation(.smooth(duration: 0.35), value: busy ?? selection)
        .animation(.smooth, value: checked)
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
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .clear.tint(.blue.opacity(0.7)).interactive() : .clear.interactive(), in: .capsule)
    }
}

/// Full-width tinted glass button for a screen's main action.
struct BigButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(enabled ? .white : .secondary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(enabled ? .clear.tint(tint.opacity(0.7)).interactive() : .clear, in: .capsule)
    }
}

/// Round glass button with a symbol, for steppers and transport controls.
struct RoundButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.title3.weight(.semibold)).frame(width: 48, height: 48).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .circle)
    }
}
