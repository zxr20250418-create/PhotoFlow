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
        completion(sampleEntry(isRunning: true))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoFlowWidgetEntry>) -> Void) {
        let entry = sampleEntry(isRunning: false)
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func sampleEntry(isRunning: Bool) -> PhotoFlowWidgetEntry {
        PhotoFlowWidgetEntry(
            date: Date(),
            isRunning: isRunning,
            elapsedText: "12:34",
            lastUpdated: Date()
        )
    }
}

struct PhotoFlowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoFlowWidgetProvider.Entry
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private var statusText: String {
        entry.isRunning ? "运行中" : "已停止"
    }

    private var shortStatusText: String {
        entry.isRunning ? "运行" : "停止"
    }

    private var updatedText: String {
        "更新 \(Self.timeFormatter.string(from: entry.lastUpdated))"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Text(shortStatusText)
                        .font(.caption2)
                    Text(entry.elapsedText)
                        .font(.caption2.monospacedDigit())
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                    Text("用时 \(entry.elapsedText)")
                        .font(.caption2.monospacedDigit())
                    Text(updatedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .accessoryCorner:
                VStack(spacing: 2) {
                    Text(entry.elapsedText)
                        .font(.caption2.monospacedDigit())
                    Text(shortStatusText)
                        .font(.caption2)
                }
            default:
                VStack(spacing: 2) {
                    Text(statusText)
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
    let kind = "PhotoFlowWatchWidget"

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

#if os(watchOS)
#Preview("Accessory Corner", as: .accessoryCorner) {
    PhotoFlowWatchWidget()
} timeline: {
    PhotoFlowWidgetEntry(date: Date(), isRunning: true, elapsedText: "12:34", lastUpdated: Date())
}
#endif
