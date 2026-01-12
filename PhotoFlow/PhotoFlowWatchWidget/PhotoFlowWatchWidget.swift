import SwiftUI
import WidgetKit

private enum WidgetStateStore {
    static let appGroupId = "group.com.zhengxinrong.photoflow"
    static let widgetKind = "PhotoFlowWatchWidget"
    static let keyIsRunning = "pf_widget_isRunning"
    static let keyStartedAt = "pf_widget_startedAt"
    static let keyLastUpdatedAt = "pf_widget_lastUpdatedAt"
    static let keyStage = "pf_widget_stage"
    static let stageShooting = "shooting"
    static let stageSelecting = "selecting"
    static let stageStopped = "stopped"

    static var isAvailable: Bool {
        UserDefaults(suiteName: appGroupId) != nil
    }

    static func normalizedStage(_ value: String?) -> String {
        switch value {
        case stageShooting, stageSelecting, stageStopped:
            return value ?? stageStopped
        default:
            return stageStopped
        }
    }

    static func readState(now: Date = Date()) -> (isRunning: Bool, startedAt: Date?, lastUpdatedAt: Date, stage: String) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return (false, nil, now, stageStopped)
        }
        let isRunning = defaults.bool(forKey: keyIsRunning)
        let startedSeconds = defaults.object(forKey: keyStartedAt) as? Double
        let lastUpdatedSeconds = defaults.object(forKey: keyLastUpdatedAt) as? Double
        let stage = normalizedStage(defaults.string(forKey: keyStage))
        let startedAt = startedSeconds.map { Date(timeIntervalSince1970: $0) }
        let lastUpdatedAt = lastUpdatedSeconds.map { Date(timeIntervalSince1970: $0) } ?? now
        return (isRunning, startedAt, lastUpdatedAt, stage)
    }
}

struct PhotoFlowWidgetEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let elapsedText: String
    let lastUpdated: Date
    let stage: String
}

struct PhotoFlowWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoFlowWidgetEntry {
        sampleEntry(isRunning: true, stage: WidgetStateStore.stageShooting)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoFlowWidgetEntry) -> Void) {
        completion(entryFromStore())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoFlowWidgetEntry>) -> Void) {
        let entry = entryFromStore()
        completion(Timeline(entries: [entry], policy: .after(nextRefreshDate(from: entry))))
    }

    private func sampleEntry(isRunning: Bool, stage: String) -> PhotoFlowWidgetEntry {
        PhotoFlowWidgetEntry(
            date: Date(),
            isRunning: isRunning,
            elapsedText: "12:34",
            lastUpdated: Date(),
            stage: stage
        )
    }

    private func entryFromStore() -> PhotoFlowWidgetEntry {
        let now = Date()
        guard WidgetStateStore.isAvailable else {
            return sampleEntry(isRunning: true, stage: WidgetStateStore.stageShooting)
        }
        let state = WidgetStateStore.readState(now: now)
        let elapsedText = formatElapsed(isRunning: state.isRunning, startedAt: state.startedAt, now: now)
        return PhotoFlowWidgetEntry(
            date: now,
            isRunning: state.isRunning,
            elapsedText: elapsedText,
            lastUpdated: state.lastUpdatedAt,
            stage: state.stage
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private var statusText: String {
        switch WidgetStateStore.normalizedStage(entry.stage) {
        case WidgetStateStore.stageSelecting:
            return "选片中"
        case WidgetStateStore.stageShooting:
            return "拍摄中"
        default:
            return "已停止"
        }
    }

    private var shortStatusText: String {
        switch WidgetStateStore.normalizedStage(entry.stage) {
        case WidgetStateStore.stageSelecting:
            return "选片"
        case WidgetStateStore.stageShooting:
            return "拍摄"
        default:
            return "停止"
        }
    }

    private var updatedText: String {
        "更新 \(Self.timeFormatter.string(from: entry.lastUpdated))"
    }

    private var widgetURL: URL? {
        let stage = WidgetStateStore.normalizedStage(entry.stage)
        return URL(string: "photoflow://stage/\(stage)")
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
#if os(watchOS)
            case .accessoryCorner:
                VStack(spacing: 2) {
                    Text(entry.elapsedText)
                        .font(.caption2.monospacedDigit())
                    Text(shortStatusText)
                        .font(.caption2)
                }
#endif
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
        .widgetURL(widgetURL)
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
#if os(watchOS)
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner
        ])
#else
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular
        ])
#endif
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
    PhotoFlowWidgetEntry(
        date: Date(),
        isRunning: true,
        elapsedText: "12:34",
        lastUpdated: Date(),
        stage: WidgetStateStore.stageShooting
    )
}

#Preview("Accessory Rectangular", as: .accessoryRectangular) {
    PhotoFlowWatchWidget()
} timeline: {
    PhotoFlowWidgetEntry(
        date: Date(),
        isRunning: false,
        elapsedText: "12:34",
        lastUpdated: Date(),
        stage: WidgetStateStore.stageStopped
    )
}

#if os(watchOS)
#Preview("Accessory Corner", as: .accessoryCorner) {
    PhotoFlowWatchWidget()
} timeline: {
    PhotoFlowWidgetEntry(
        date: Date(),
        isRunning: true,
        elapsedText: "12:34",
        lastUpdated: Date(),
        stage: WidgetStateStore.stageSelecting
    )
}
#endif
