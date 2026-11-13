import WidgetKit
import SwiftUI
import Rex5Kit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: EarbudSnapshot
}

/// The app reloads the widgets when the snapshot visibly changes, so the timeline never refreshes on its own.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: SnapshotFile.defaultURL.flatMap(SnapshotFile.read) ?? EarbudSnapshot())
    }
}

struct Rex5Widget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Rex5Widget", provider: SnapshotProvider()) { entry in
            Rex5WidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("REX5")
        .description("Battery and connection for your REX5 earbuds.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct Rex5WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: EarbudSnapshot

    var body: some View {
        content.containerBackground(for: .widget) {
            // The app's plain background; with clear or tinted Home Screen icons iOS swaps it for its own glass.
            if family == .accessoryRectangular { Color.clear } else { Color(.systemGroupedBackground) }
        }
    }

    @ViewBuilder private var content: some View {
        if family == .accessoryRectangular {
            VStack(alignment: .leading) {
                Text("REX5  L \(snapshot.batteryText(snapshot.leftBattery))  R \(snapshot.batteryText(snapshot.rightBattery))")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(snapshot.lockStatusLine)
            }
        } else if family == .systemSmall {
            small
        } else {
            medium
        }
    }

    private var rings: some View {
        HStack(spacing: 12) {
            // "In case" gets cut off in a ring this size.
            BatteryRing(side: "L", percent: snapshot.leftBattery, text: snapshot.batteryText(snapshot.leftBattery, inCase: "Case"), size: 54)
            BatteryRing(side: "R", percent: snapshot.rightBattery, text: snapshot.batteryText(snapshot.rightBattery, inCase: "Case"), size: 54)
        }
    }

    private var small: some View {
        VStack(spacing: 8) {
            rings
            Text(snapshot.lockStatusLine)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frosted(Capsule())
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                rings
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.statusLine).font(.headline).lineLimit(2)
                    if let other = snapshot.otherConnectedNames.first {
                        Text("Also: \(other)").font(.caption).lineLimit(1)
                    }
                    Text("updated \(Text(snapshot.batteryReadAt ?? snapshot.updatedAt, style: .relative)) ago")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if snapshot.isConnectedHere {
                    pill("Disconnect", "xmark.circle", .disconnect)
                } else {
                    pill("Connect", "link", .connect)
                }
                pill("Troubleshoot", "wrench.and.screwdriver", .tools)
            }
        }
    }

    private func pill(_ title: String, _ icon: String, _ link: DeepLink) -> some View {
        Link(destination: link.url) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
                .frosted(Capsule())
        }
    }
}

extension View {
    /// Draws a frosted-glass shape behind the content.
    // ponytail: widgets can't run live Liquid Glass (glassEffect), so this imitates it; switch if WidgetKit gains it.
    func frosted<S: InsettableShape>(_ shape: S) -> some View {
        modifier(Frosted(shape: shape))
    }
}

private struct Frosted<S: InsettableShape>: ViewModifier {
    @Environment(\.widgetRenderingMode) private var mode
    let shape: S

    func body(content: Content) -> some View {
        if mode == .fullColor {
            content
                .background(Color(.secondarySystemGroupedBackground).opacity(0.75), in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.6))
        } else {
            content  // clear or tinted Home Screen: iOS already draws the widget as glass
        }
    }
}

extension EarbudSnapshot {
    static let sample = EarbudSnapshot(
        link: .connected, leftBattery: 80, rightBattery: 75, batteryReadAt: .now,
        devices: [PairedDevice(index: 0, name: "This iPhone", isConnected: true)], thisPhoneName: "This iPhone")
}

#Preview("Medium", as: .systemMedium) {
    Rex5Widget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
    SnapshotEntry(date: .now, snapshot: EarbudSnapshot(link: .disconnected))
}

#Preview("Small", as: .systemSmall) {
    Rex5Widget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}
