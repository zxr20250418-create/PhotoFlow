//
//  ContentView.swift
//  PhotoFlow
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import Combine
import SwiftUI
import WatchConnectivity

@MainActor
final class WatchSyncStore: NSObject, ObservableObject, WCSessionDelegate {
    fileprivate enum StageSyncKey {
        static let stage = "pf_widget_stage"
        static let isRunning = "pf_widget_isRunning"
        static let startedAt = "pf_widget_startedAt"
        static let lastUpdatedAt = "pf_widget_lastUpdatedAt"
        static let stageShooting = "shooting"
        static let stageSelecting = "selecting"
        static let stageStopped = "stopped"
    }

    struct SessionEvent: Identifiable {
        let id = UUID()
        let event: String
        let timestamp: TimeInterval
    }

    @Published var isOnDuty = false
    @Published var incomingEvent: SessionEvent?
#if DEBUG
    @Published var debugLastSentPayload: String = "—"
    @Published var debugSessionStatus: String = "—"
#endif

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
#if DEBUG
        updateDebugStatus(for: WCSession.default)
#endif
    }

    func setOnDuty(_ value: Bool) {
        isOnDuty = value
        sendOnDutyUpdate(value)
    }

    private func sendOnDutyUpdate(_ value: Bool) {
        guard WCSession.isSupported() else { return }
        let payload: [String: Any] = [
            "isOnDuty": value,
            "ts": Int(Date().timeIntervalSince1970)
        ]
#if DEBUG
        debugLastSentPayload = formatDebugPayload(payload)
        updateDebugStatus(for: WCSession.default)
#endif
        do {
            try WCSession.default.updateApplicationContext(payload)
        } catch {
            // Non-fatal; watch will catch up on next change.
        }
    }

    func sendStageSync(stage: String, isRunning: Bool, startedAt: Date?, lastUpdatedAt: Date) {
        guard WCSession.isSupported() else { return }
        var payload: [String: Any] = [
            StageSyncKey.stage: stage,
            StageSyncKey.isRunning: isRunning,
            StageSyncKey.lastUpdatedAt: lastUpdatedAt.timeIntervalSince1970
        ]
        if let startedAt {
            payload[StageSyncKey.startedAt] = startedAt.timeIntervalSince1970
        }
        let session = WCSession.default
#if DEBUG
        debugLastSentPayload = formatDebugPayload(payload)
        updateDebugStatus(for: session)
#endif
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("WCSession updateApplicationContext failed: \(error.localizedDescription)")
        }
        let usedReachable = session.isReachable
        if usedReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("WCSession sendMessage failed: \(error.localizedDescription)")
            }
        }
        print("WCSession sent state payload=\(payload) reachable=\(usedReachable)")
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }

#if DEBUG
    func sessionReachabilityDidChange(_ session: WCSession) {
        updateDebugStatus(for: session)
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        updateDebugStatus(for: session)
    }
#endif

#if DEBUG
    private func updateDebugStatus(for session: WCSession) {
        let activation: String
        switch session.activationState {
        case .activated:
            activation = "activated"
        case .inactive:
            activation = "inactive"
        case .notActivated:
            activation = "notActivated"
        @unknown default:
            activation = "unknown"
        }
        let parts = [
            "activation=\(activation)",
            "reachable=\(session.isReachable)",
            "paired=\(session.isPaired)",
            "watchAppInstalled=\(session.isWatchAppInstalled)"
        ]
        debugSessionStatus = parts.joined(separator: "\n")
    }

    private func formatDebugPayload(_ payload: [String: Any]) -> String {
        let parts = payload
            .map { "\($0.key)=\(String(describing: $0.value))" }
            .sorted()
        return parts.joined(separator: "\n")
    }
#endif

    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleSessionPayload(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleSessionPayload(userInfo)
    }

    private func handleSessionPayload(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String, type == "session_event" else { return }
        guard let event = payload["event"] as? String else { return }
        let timestamp: TimeInterval?
        if let value = payload["t"] as? Int {
            timestamp = TimeInterval(value)
        } else if let value = payload["t"] as? Double {
            timestamp = value
        } else {
            timestamp = nil
        }
        guard let resolvedTimestamp = timestamp else { return }
        Task { @MainActor in
            incomingEvent = SessionEvent(event: event, timestamp: resolvedTimestamp)
        }
    }
}

struct ContentView: View {
    enum Stage {
        case idle
        case shooting
        case selecting
        case ended
    }

    struct Session {
        var shootingStart: Date?
        var selectingStart: Date?
        var endedAt: Date?
    }

    struct SessionSummary: Identifiable {
        let id: String
        var shootingStart: Date?
        var selectingStart: Date?
        var endedAt: Date?
    }

    enum ActiveAlert: Identifiable {
        case notOnDuty
        case cannotEndWhileShooting

        var id: String {
            switch self {
            case .notOnDuty:
                return "notOnDuty"
            case .cannotEndWhileShooting:
                return "cannotEndWhileShooting"
            }
        }

        var message: String {
            switch self {
            case .notOnDuty:
                return "未上班，无法开始记录"
            case .cannotEndWhileShooting:
                return "拍摄中不可直接结束"
            }
        }
    }

    @State private var stage: Stage = .idle
    @State private var session = Session()
    @State private var activeAlert: ActiveAlert?
    @State private var now = Date()
    @State private var sessionSummaries: [SessionSummary] = []
#if DEBUG
    @State private var showDebugPanel = false
#endif
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @ObservedObject var syncStore: WatchSyncStore

    init(syncStore: WatchSyncStore) {
        self.syncStore = syncStore
    }

    var body: some View {
        let durations = computeDurations(now: now)

        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(syncStore.isOnDuty ? stageLabel : "未上班")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("总时长 \(format(durations.total)) · 当前阶段 \(format(durations.currentStage))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(action: handlePrimaryAction) {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            VStack(alignment: .leading, spacing: 8) {
                Text("会话时间线")
                    .font(.headline)
                if sessionSummaries.isEmpty {
                    Text("暂无记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(sessionSummaries.reversed().enumerated()), id: \.element.id) { index, summary in
                        VStack(alignment: .leading, spacing: 4) {
                            let displayIndex = index + 1
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(sessionTitle(for: displayIndex))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                if let startTime = sessionStartTime(for: summary) {
                                    Text(formatTimelineTime(startTime))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(timelineRows(for: summary), id: \.label) { row in
                                HStack {
                                    Text(formatTimelineTime(row.time))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(row.label)
                                        .font(.caption)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(syncStore.isOnDuty ? "下班" : "上班") {
                let nextOnDuty = !syncStore.isOnDuty
                syncStore.setOnDuty(nextOnDuty)
                if !nextOnDuty {
                    resetSession()
                }
            }
            .buttonStyle(.bordered)

#if DEBUG
            Button(action: { showDebugPanel.toggle() }) {
                Text("Debug")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .opacity(0.4)

            if showDebugPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("lastSentPayload")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(syncStore.debugLastSentPayload)
                        .font(.caption2)
                        .textSelection(.enabled)

                    Text("sessionStatus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(syncStore.debugSessionStatus)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
#endif
        }
        .padding()
        .alert(item: $activeAlert) { alert in
            Alert(title: Text(alert.message))
        }
        .onReceive(ticker) { now = $0 }
        .onReceive(syncStore.$incomingEvent) { event in
            guard let event = event else { return }
            applySessionEvent(event)
        }
    }

    private var stageLabel: String {
        switch stage {
        case .idle:
            return ""
        case .shooting:
            return "拍摄"
        case .selecting:
            return "选片"
        case .ended:
            return "已结束"
        }
    }

    private var primaryButtonTitle: String {
        if !syncStore.isOnDuty {
            return "开始拍摄"
        }
        switch stage {
        case .idle:
            return "开始拍摄"
        case .shooting:
            return "开始选片"
        case .selecting:
            return "结束"
        case .ended:
            return "开始拍摄"
        }
    }

    private func handlePrimaryAction() {
        guard syncStore.isOnDuty else {
            activeAlert = .notOnDuty
            return
        }
        let now = Date()
        switch stage {
        case .idle:
            stage = .shooting
            session.shootingStart = now
        case .shooting:
            stage = .selecting
            session.selectingStart = now
        case .selecting:
            stage = .ended
            session.endedAt = now
        case .ended:
            session = Session()
            session.shootingStart = now
            stage = .shooting
        }
        updateSessionSummary(for: stage, at: now)
        syncStageState(now: now)
    }

    private func resetSession() {
        endActiveSessionIfNeeded(at: Date())
        stage = .idle
        session = Session()
        syncStageState(now: Date())
    }

    private func applySessionEvent(_ event: WatchSyncStore.SessionEvent) {
        let timestampSeconds = normalizeEpochSeconds(event.timestamp)
        let timestamp = Date(timeIntervalSince1970: timestampSeconds)
        switch event.event {
        case "startShooting":
            session = Session()
            session.shootingStart = timestamp
            stage = .shooting
            updateSessionSummary(for: .shooting, at: timestamp)
        case "startSelecting":
            session.selectingStart = timestamp
            stage = .selecting
            updateSessionSummary(for: .selecting, at: timestamp)
        case "end":
            session.endedAt = timestamp
            stage = .ended
            updateSessionSummary(for: .ended, at: timestamp)
        default:
            break
        }
    }

    private func normalizeEpochSeconds(_ value: TimeInterval) -> TimeInterval {
        if value > 1_000_000_000_000 {
            return value / 1000
        }
        return value
    }

    private func computeDurations(now: Date) -> (total: TimeInterval, currentStage: TimeInterval) {
        guard let shootingStart = session.shootingStart else {
            return (0, 0)
        }
        let endTime = session.endedAt ?? now
        let total = max(0, endTime.timeIntervalSince(shootingStart))

        let currentStage: TimeInterval
        switch stage {
        case .shooting:
            currentStage = max(0, now.timeIntervalSince(shootingStart))
        case .selecting:
            if let selectingStart = session.selectingStart {
                currentStage = max(0, now.timeIntervalSince(selectingStart))
            } else {
                currentStage = 0
            }
        case .idle, .ended:
            currentStage = 0
        }

        return (total, currentStage)
    }

    private func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func updateSessionSummary(for stage: Stage, at timestamp: Date) {
        switch stage {
        case .shooting:
            if let index = targetSessionIndex(for: timestamp) {
                let current = sessionSummaries[index].shootingStart
                if current == nil || timestamp < current! {
                    sessionSummaries[index].shootingStart = timestamp
                }
            } else {
                let sessionId = makeSessionId(startedAt: timestamp)
                sessionSummaries.append(SessionSummary(
                    id: sessionId,
                    shootingStart: timestamp,
                    selectingStart: nil,
                    endedAt: nil
                ))
            }
        case .selecting:
            guard let index = targetSessionIndex(for: timestamp) else { return }
            let current = sessionSummaries[index].selectingStart
            if current == nil || timestamp < current! {
                sessionSummaries[index].selectingStart = timestamp
            }
        case .ended:
            guard let index = targetSessionIndex(for: timestamp) else { return }
            let current = sessionSummaries[index].endedAt
            if current == nil || timestamp > current! {
                sessionSummaries[index].endedAt = timestamp
            }
        case .idle:
            break
        }
        sortSessionSummaries()
    }

    private func endActiveSessionIfNeeded(at timestamp: Date) {
        guard let index = activeSessionIndex() else { return }
        let current = sessionSummaries[index].endedAt
        if current == nil || timestamp > current! {
            sessionSummaries[index].endedAt = timestamp
        }
        sortSessionSummaries()
    }

    private func activeSessionIndex() -> Int? {
        sessionSummaries.lastIndex(where: { $0.endedAt == nil })
    }

    private func targetSessionIndex(for timestamp: Date) -> Int? {
        if let activeIndex = activeSessionIndex() {
            if let activeStart = sessionStartTime(for: sessionSummaries[activeIndex]),
               timestamp < activeStart,
               let endedIndex = recentEndedSessionIndex(for: timestamp) {
                return endedIndex
            }
            return activeIndex
        }
        return recentEndedSessionIndex(for: timestamp)
    }

    private func recentEndedSessionIndex(for timestamp: Date) -> Int? {
        guard let index = sessionSummaries.indices.last else { return nil }
        guard let endedAt = sessionSummaries[index].endedAt else { return nil }
        return timestamp <= endedAt ? index : nil
    }

    private func sortSessionSummaries() {
        sessionSummaries.sort { sessionSortKey(for: $0) < sessionSortKey(for: $1) }
    }

    private func sessionStartTime(for summary: SessionSummary) -> Date? {
        [summary.shootingStart, summary.selectingStart, summary.endedAt].compactMap { $0 }.min()
    }

    private func sessionSortKey(for summary: SessionSummary) -> Date {
        sessionStartTime(for: summary) ?? Date.distantPast
    }

    private func timelineRows(for summary: SessionSummary) -> [(label: String, time: Date)] {
        var rows: [(label: String, time: Date)] = []
        if let shootingStart = summary.shootingStart {
            rows.append((label: "拍摄开始", time: shootingStart))
        }
        if let selectingStart = summary.selectingStart {
            rows.append((label: "选片开始", time: selectingStart))
        }
        if let endedAt = summary.endedAt {
            rows.append((label: "结束", time: endedAt))
        }
        return rows.sorted { $0.time < $1.time }
    }

    private func formatTimelineTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func sessionTitle(for displayIndex: Int) -> String {
        "第\(chineseNumber(displayIndex))单"
    }

    private func chineseNumber(_ value: Int) -> String {
        let digits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard value > 0 else { return "零" }
        if value < 10 {
            return digits[value]
        }
        if value < 20 {
            return value == 10 ? "十" : "十" + digits[value % 10]
        }
        if value < 100 {
            let tens = value / 10
            let ones = value % 10
            let tensText = digits[tens] + "十"
            return ones == 0 ? tensText : tensText + digits[ones]
        }
        return String(value)
    }

    private func makeSessionId(startedAt: Date) -> String {
        let base = "session-\(Int(startedAt.timeIntervalSince1970 * 1000))"
        if sessionSummaries.contains(where: { $0.id == base }) {
            return base + "-" + UUID().uuidString
        }
        return base
    }

    private func syncStageState(now: Date) {
        let stageValue: String
        switch stage {
        case .shooting:
            stageValue = WatchSyncStore.StageSyncKey.stageShooting
        case .selecting:
            stageValue = WatchSyncStore.StageSyncKey.stageSelecting
        case .idle, .ended:
            stageValue = WatchSyncStore.StageSyncKey.stageStopped
        }
        let isRunning = stageValue != WatchSyncStore.StageSyncKey.stageStopped
        let startedAt = isRunning ? session.shootingStart : nil
        syncStore.sendStageSync(
            stage: stageValue,
            isRunning: isRunning,
            startedAt: startedAt,
            lastUpdatedAt: now
        )
    }
}

#Preview {
    ContentView(syncStore: WatchSyncStore())
}
