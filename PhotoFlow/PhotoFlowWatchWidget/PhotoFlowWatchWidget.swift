import SwiftUI
import WidgetKit

private enum WidgetStateStore {
    static let appGroupId = "group.com.zhengxinrong.photoflow"
    static let widgetKind = "PhotoFlowWatchWidget"
    static let keyIsRunning = "pf_widget_isRunning"
    static let keyStartedAt = "pf_widget_startedAt"
    static let keyLastUpdatedAt = "pf_widget_lastUpdatedAt"
    static let keyStage = "pf_widget_stage"
    static let keyCanonicalStage = "pf_canonical_stage"
    static let keyCanonicalStageStartAt = "pf_canonical_stageStartAt"
    static let keyCanonicalUpdatedAt = "pf_canonical_updatedAt"
    static let keyCanonicalRevision = "pf_canonical_revision"
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

    static func readCanonicalState(now: Date = Date()) -> (stage: String, stageStartAt: Date?, updatedAt: Date, revision: Int64)? {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        guard let stageValue = defaults.string(forKey: keyCanonicalStage) else { return nil }
        let stage = normalizedStage(stageValue)
        let startSeconds = readSeconds(defaults.object(forKey: keyCanonicalStageStartAt))
        let updatedSeconds = readSeconds(defaults.object(forKey: keyCanonicalUpdatedAt))
        let revision = readInt64(defaults.object(forKey: keyCanonicalRevision))
        return (
            stage: stage,
            stageStartAt: startSeconds.map { Date(timeIntervalSince1970: $0) },
            updatedAt: updatedSeconds.map { Date(timeIntervalSince1970: $0) } ?? now,
            revision: revision ?? Int64((updatedSeconds ?? now.timeIntervalSince1970) * 1000)
        )
    }

    static func debugSummary(now: Date = Date()) -> String {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return "suiteOK=false raw=nil type=nil value=nil epoch=0"
        }
        let rawStage = defaults.string(forKey: keyCanonicalStage)
        let rawStart = defaults.object(forKey: keyCanonicalStageStartAt)
        let parsed = readSeconds(rawStart)
        return [
            "suiteOK=true",
            "rawStage=\(rawStage ?? "nil")",
            "rawStartType=\(rawStartTypeLabel(rawStart))",
            "rawStartValue=\(rawStartValueLabel(rawStart))",
            "epoch=\(Int(parsed ?? 0))"
        ].joined(separator: " ")
    }

    static func readSeconds(_ value: Any?) -> Double? {
        if let date = value as? Date {
            return date.timeIntervalSince1970
        }
        if let seconds = value as? Double {
            return normalizeEpoch(seconds)
        }
        if let seconds = value as? Int {
            return normalizeEpoch(Double(seconds))
        }
        if let seconds = value as? Int64 {
            return normalizeEpoch(Double(seconds))
        }
        return nil
    }

    private static func normalizeEpoch(_ value: Double) -> Double {
        if value > 100_000_000_000 {
            return value / 1000
        }
        return value
    }

    private static func rawStartTypeLabel(_ value: Any?) -> String {
        guard let value else { return "nil" }
        if value is Date { return "Date" }
        if value is Double { return "Double" }
        if value is Int64 { return "Int64" }
        if value is Int { return "Int" }
        if let number = value as? NSNumber {
            switch CFNumberGetType(number) {
            case .floatType, .float32Type, .float64Type, .doubleType, .cgFloatType:
                return "Double"
            case .sInt64Type, .longLongType, .cfIndexType, .nsIntegerType:
                return "Int64"
            case .sInt8Type, .sInt16Type, .sInt32Type, .shortType, .intType, .longType:
                return "Int"
            default:
                return "NSNumber"
            }
        }
        return String(describing: type(of: value))
    }

    private static func rawStartValueLabel(_ value: Any?) -> String {
        guard let value else { return "nil" }
        if let date = value as? Date {
            return String(Int(date.timeIntervalSince1970))
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return String(describing: value)
    }

    static func readInt64(_ value: Any?) -> Int64? {
        if let num = value as? Int64 {
            return num
        }
        if let num = value as? Int {
            return Int64(num)
        }
        if let num = value as? Double {
            return Int64(num)
        }
        return nil
    }
}

struct PhotoFlowWidgetEntry: TimelineEntry {
    let date: Date
    let isRunning: Bool
    let startedAt: Date?
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
            startedAt: isRunning ? Date() : nil,
            lastUpdated: Date(),
            stage: stage
        )
    }

    private func entryFromStore() -> PhotoFlowWidgetEntry {
        let now = Date()
        guard WidgetStateStore.isAvailable else {
            return sampleEntry(isRunning: true, stage: WidgetStateStore.stageShooting)
        }
        if let canonical = WidgetStateStore.readCanonicalState(now: now) {
            let isRunning = canonical.stage != WidgetStateStore.stageStopped && canonical.stageStartAt != nil
            return PhotoFlowWidgetEntry(
                date: now,
                isRunning: isRunning,
                startedAt: canonical.stageStartAt,
                lastUpdated: canonical.updatedAt,
                stage: canonical.stage
            )
        }
        let state = WidgetStateStore.readState(now: now)
        return PhotoFlowWidgetEntry(
            date: now,
            isRunning: state.isRunning,
            startedAt: state.startedAt,
            lastUpdated: state.lastUpdatedAt,
            stage: state.stage
        )
    }

    private func nextRefreshDate(from entry: PhotoFlowWidgetEntry) -> Date {
        if entry.isRunning {
            return entry.date.addingTimeInterval(45)
        }
        return entry.date.addingTimeInterval(12 * 60)
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

    private func elapsedTextView(font: Font) -> some View {
        let normalizedStage = WidgetStateStore.normalizedStage(entry.stage)
        let isRunningStage = normalizedStage == WidgetStateStore.stageShooting
            || normalizedStage == WidgetStateStore.stageSelecting
        return Group {
            if isRunningStage, let startedAt = entry.startedAt {
                Text(timerInterval: startedAt...startedAt.addingTimeInterval(24 * 60 * 60), countsDown: false)
            } else if let startedAt = entry.startedAt {
                Text(staticDurationText(from: startedAt, to: entry.lastUpdated))
            } else {
                Text("--")
            }
        }
        .font(font.monospacedDigit())
    }

    private func staticDurationText(from start: Date, to end: Date) -> String {
        let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

#if DEBUG
    private var debugLine: String {
        WidgetStateStore.debugSummary()
    }
#endif

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Text(shortStatusText)
                        .font(.caption2)
                    elapsedTextView(font: .caption2)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                    HStack(spacing: 2) {
                        Text("用时")
                            .font(.caption2)
                        elapsedTextView(font: .caption2)
                    }
                    Text(updatedText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
#if DEBUG
                    Text(debugLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
#endif
                }
#if os(watchOS)
            case .accessoryCorner:
                VStack(spacing: 2) {
                    Text(shortStatusText)
                        .font(.caption2)
                    elapsedTextView(font: .caption2)
                }
#endif
            default:
                VStack(spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                    elapsedTextView(font: .caption2)
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
        startedAt: Date(),
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
        startedAt: nil,
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
        startedAt: Date(),
        lastUpdated: Date(),
        stage: WidgetStateStore.stageSelecting
    )
}
#endif
