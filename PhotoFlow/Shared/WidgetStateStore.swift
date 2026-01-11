import Foundation

enum WidgetStateStore {
    static let appGroupId = "group.com.zhengxinrong.photoflow"
    static let widgetKind = "PhotoFlowWatchWidget"
    static let keyIsRunning = "pf_widget_isRunning"
    static let keyStartedAt = "pf_widget_startedAt"
    static let keyLastUpdatedAt = "pf_widget_lastUpdatedAt"

    static var isAvailable: Bool {
        UserDefaults(suiteName: appGroupId) != nil
    }

    static func readState(now: Date = Date()) -> (isRunning: Bool, startedAt: Date?, lastUpdatedAt: Date) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return (false, nil, now)
        }
        let isRunning = defaults.bool(forKey: keyIsRunning)
        let startedSeconds = defaults.object(forKey: keyStartedAt) as? Double
        let lastUpdatedSeconds = defaults.object(forKey: keyLastUpdatedAt) as? Double
        let startedAt = startedSeconds.map { Date(timeIntervalSince1970: $0) }
        let lastUpdatedAt = lastUpdatedSeconds.map { Date(timeIntervalSince1970: $0) } ?? now
        return (isRunning, startedAt, lastUpdatedAt)
    }

    static func writeState(
        isRunning: Bool,
        startedAt: Date?,
        lastUpdatedAt: Date = Date()
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        defaults.set(isRunning, forKey: keyIsRunning)
        if let startedAt {
            defaults.set(startedAt.timeIntervalSince1970, forKey: keyStartedAt)
        } else {
            defaults.removeObject(forKey: keyStartedAt)
        }
        defaults.set(lastUpdatedAt.timeIntervalSince1970, forKey: keyLastUpdatedAt)
    }
}
