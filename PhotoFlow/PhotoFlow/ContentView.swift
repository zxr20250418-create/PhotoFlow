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
    @Published var sessionActivationState: WCSessionActivationState = .notActivated
    @Published var sessionReachable = false
    @Published var lastSyncAt: Date?
#if DEBUG
    @Published var debugLastSentPayload: String = "—"
    @Published var debugSessionStatus: String = "—"
#endif

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        updateSessionStatus(for: session)
#if DEBUG
        updateDebugStatus(for: session)
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
        lastSyncAt = lastUpdatedAt
        updateSessionStatus(for: session)
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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        updateSessionStatus(for: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        updateSessionStatus(for: session)
#if DEBUG
        updateDebugStatus(for: session)
#endif
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        updateSessionStatus(for: session)
#if DEBUG
        updateDebugStatus(for: session)
#endif
    }

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

    private func updateSessionStatus(for session: WCSession) {
        sessionActivationState = session.activationState
        sessionReachable = session.isReachable
    }

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
        let elapsedText = isStageRunning ? format(durations.total) : "00:00"

        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(stageDisplayText)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("用时 \(elapsedText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !syncStore.isOnDuty {
                    Text("未上班")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text("连接 \(connectionStatusText)")
                Spacer(minLength: 8)
                Text("最近同步 \(formatSyncTime(syncStore.lastSyncAt))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 12) {
                Button("拍摄") {
                    handleStageSelection(.shooting)
                }
                Button("选片") {
                    handleStageSelection(.selecting)
                }
                Button("停止") {
                    handleStageSelection(.ended)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)

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

    private var stageDisplayText: String {
        switch stage {
        case .shooting:
            return "拍摄"
        case .selecting:
            return "选片"
        case .idle, .ended:
            return "停止"
        }
    }

    private var isStageRunning: Bool {
        stage == .shooting || stage == .selecting
    }

    private var connectionStatusText: String {
        guard syncStore.sessionActivationState == .activated else {
            return "未连接"
        }
        return syncStore.sessionReachable ? "已连接" : "未连接"
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
        syncStageState(now: now)
    }

    private func handleStageSelection(_ targetStage: Stage) {
        guard syncStore.isOnDuty else {
            activeAlert = .notOnDuty
            return
        }
        let now = Date()
        switch targetStage {
        case .shooting:
            session.shootingStart = session.shootingStart ?? now
            session.selectingStart = nil
            session.endedAt = nil
        case .selecting:
            session.shootingStart = session.shootingStart ?? now
            session.selectingStart = session.selectingStart ?? now
            session.endedAt = nil
        case .ended:
            session.endedAt = now
        case .idle:
            break
        }
        stage = targetStage
        syncStageState(now: now)
    }

    private func resetSession() {
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
        case "startSelecting":
            session.selectingStart = timestamp
            stage = .selecting
        case "end":
            session.endedAt = timestamp
            stage = .ended
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

    private func formatSyncTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm:ss"
        return formatter.string(from: date)
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
