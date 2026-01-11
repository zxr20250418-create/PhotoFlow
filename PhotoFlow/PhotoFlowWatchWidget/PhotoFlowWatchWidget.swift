import SwiftUI
import WidgetKit

struct PhotoFlowWidgetEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let elapsedText: String
    let lastUpdated: Date
}

struct PhotoFlowWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoFlowWidgetEntry {
        sampleEntry(isRunning: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoFlowWidgetEntry) -> Void) {
        completion(entryFromStore())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoFlowWidgetEntry>) -> Void) {
        let entry = entryFromStore()
        completion(Timeline(entries: [entry], policy: .after(nextRefreshDate(from: entry))))
    }

    private func sampleEntry(isRunning: Bool) -> PhotoFlowWidgetEntry {
        PhotoFlowWidgetEntry(
            date: Date(),
            isRunning: isRunning,
            elapsedText: "12:34",
            lastUpdated: Date()
        )
    }

    private func entryFromStore() -> PhotoFlowWidgetEntry {
        let now = Date()
        guard WidgetStateStore.isAvailable else {
            return sampleEntry(isRunning: true)
        }
        let state = WidgetStateStore.readState(now: now)
        let elapsedText = formatElapsed(isRunning: state.isRunning, startedAt: state.startedAt, now: now)
        return PhotoFlowWidgetEntry(
            date: now,
            isRunning: state.isRunning,
            elapsedText: elapsedText,
            lastUpdated: state.lastUpdatedAt
        )
    }

    private func formatElapsed(isRunning: Bool, startedAt: Date?, now: Date) -> String {
        guard isRunning, let startedAt else { return "00:00" }
        let totalSeconds = max(0, Int(now.timeIntervalSince(startedAt)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func nextRefreshDate(from entry: PhotoFlowWidgetEntry) -> Date {
        if entry.isRunning {
            return entry.date.addingTimeInterval(60)
        }
        return entry.date.addingTimeInterval(15 * 60)
    }
}

struct PhotoFlowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoFlowWidgetProvider.Entry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Text(entry.isRunning ? "Running" : "Stopped")
                        .font(.caption2)
                    Text(entry.elapsedText)
                        .font(.caption2.monospacedDigit())
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                    Text("Elapsed \(entry.elapsedText)")
                        .font(.caption2.monospacedDigit())
                    Text(entry.lastUpdated, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .accessoryCorner:
                VStack(spacing: 2) {
                    Text(entry.elapsedText)
                        .font(.caption2.monospacedDigit())
                    Text(entry.isRunning ? "Run" : "Stop")
                        .font(.caption2)
                }
            default:
                VStack(spacing: 2) {
                    Text(entry.isRunning ? "Running" : "Stopped")
                        .font(.caption)
                    Text(entry.elapsedText)
                        .font(.caption2.monospacedDigit())
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct PhotoFlowWatchWidget: Widget {
    let kind = WidgetStateStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PhotoFlowWidgetProvider()) { entry in
            PhotoFlowWidgetView(entry: entry)
        }
        .configurationDisplayName("PhotoFlow")
        .description("Shows session status and elapsed time.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner
        ])
    }
}

@main
struct PhotoFlowWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        PhotoFlowWatchWidget()
    }
}

#Preview("Accessory Circular", as: .accessoryCircular) {
    PhotoFlowWatchWidget()
} timeline: {
    PhotoFlowWidgetEntry(date: Date(), isRunning: true, elapsedText: "12:34", lastUpdated: Date())
}

#Preview("Accessory Rectangular", as: .accessoryRectangular) {
    PhotoFlowWatchWidget()
} timeline: {
    PhotoFlowWidgetEntry(date: Date(), isRunning: false, elapsedText: "12:34", lastUpdated: Date())
}

#Preview("Accessory Corner", as: .accessoryCorner) {
    PhotoFlowWatchWidget()
} timeline: {
    PhotoFlowWidgetEntry(date: Date(), isRunning: true, elapsedText: "12:34", lastUpdated: Date())
}
