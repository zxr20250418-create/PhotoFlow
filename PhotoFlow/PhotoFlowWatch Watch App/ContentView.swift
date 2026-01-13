//
//  ContentView.swift
//  PhotoFlowWatch Watch App
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import Combine
import SwiftUI
import WatchConnectivity
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

    static func writeState(
        isRunning: Bool,
        startedAt: Date?,
        stage: String,
        lastUpdatedAt: Date = Date()
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        defaults.set(isRunning, forKey: keyIsRunning)
        if let startedAt {
            defaults.set(startedAt.timeIntervalSince1970, forKey: keyStartedAt)
        } else {
            defaults.removeObject(forKey: keyStartedAt)
        }
        defaults.set(stage, forKey: keyStage)
        defaults.set(lastUpdatedAt.timeIntervalSince1970, forKey: keyLastUpdatedAt)
    }
}

@MainActor
final class WatchSyncStore: NSObject, ObservableObject, WCSessionDelegate {
    private enum SyncOrderKey {
        static let lastAppliedAt = "pf_sync_lastAppliedAt"
    }

    struct IncomingState: Equatable {
        let stage: String
        let isRunning: Bool
        let startedAt: Date?
        let lastUpdatedAt: Date
    }

    @Published var isOnDuty = false
    @Published var incomingState: IncomingState?
#if DEBUG
    @Published var debugLastReceivedPayload: String = "—"
    @Published var debugLastAppliedAt: String = "—"
    @Published var debugSessionStatus: String = "—"
#endif

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        if session.activationState == .activated {
            applyLatestContextIfAvailable(from: session)
        }
#if DEBUG
        updateDebugStatus(for: session)
#endif
    }

    func sendSessionEvent(event: String, timestamp: TimeInterval) {
        guard WCSession.isSupported() else { return }
        let payload: [String: Any] = [
            "type": "session_event",
            "event": event,
            "t": Int(timestamp),
            "source": "watch"
        ]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard error == nil, activationState == .activated else { return }
        applyLatestContextIfAvailable(from: session)
#if DEBUG
        updateDebugStatus(for: session)
#endif
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif

    func sessionReachabilityDidChange(_ session: WCSession) {
#if DEBUG
        updateDebugStatus(for: session)
#endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let value = applicationContext["isOnDuty"] as? Bool else { return }
        Task { @MainActor in
            isOnDuty = value
        }
        applyStatePayload(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyStatePayload(message)
    }

    private func applyStatePayload(_ payload: [String: Any]) {
        let hasStateKey = payload.keys.contains(WidgetStateStore.keyStage)
            || payload.keys.contains(WidgetStateStore.keyIsRunning)
            || payload.keys.contains(WidgetStateStore.keyStartedAt)
            || payload.keys.contains(WidgetStateStore.keyLastUpdatedAt)
        guard hasStateKey else { return }

#if DEBUG
        debugLastReceivedPayload = formatDebugPayload(payload)
        updateDebugStatus(for: WCSession.default)
#endif
        let stage = normalizedStage(payload[WidgetStateStore.keyStage] as? String)
        let isRunning = payload[WidgetStateStore.keyIsRunning] as? Bool ?? (stage != WidgetStateStore.stageStopped)
        let startedAtSeconds = parseEpoch(payload[WidgetStateStore.keyStartedAt])
        let lastUpdatedSeconds = parseEpoch(payload[WidgetStateStore.keyLastUpdatedAt])
        guard shouldApplyState(lastUpdatedAtSeconds: lastUpdatedSeconds) else { return }
        let resolvedLastUpdatedSeconds = lastUpdatedSeconds ?? Date().timeIntervalSince1970
        let state = IncomingState(
            stage: stage,
            isRunning: isRunning,
            startedAt: startedAtSeconds.map { Date(timeIntervalSince1970: $0) },
            lastUpdatedAt: Date(timeIntervalSince1970: resolvedLastUpdatedSeconds)
        )
        Task { @MainActor in
            incomingState = state
        }
        print("WCSession received state stage=\(stage) running=\(isRunning)")
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
            "reachable=\(session.isReachable)"
        ]
#if os(watchOS)
        let installedLabel = "companionInstalled=\(session.isCompanionAppInstalled)"
#else
        let installedLabel = "watchAppInstalled=\(session.isWatchAppInstalled)"
#endif
        debugSessionStatus = (parts + [installedLabel]).joined(separator: "\n")
    }

    private func formatDebugPayload(_ payload: [String: Any]) -> String {
        let parts = payload
            .map { "\($0.key)=\(String(describing: $0.value))" }
            .sorted()
        return parts.joined(separator: "\n")
    }
#endif

    private func applyLatestContextIfAvailable(from session: WCSession) {
        let receivedContext = session.receivedApplicationContext
        let context = receivedContext.isEmpty ? session.applicationContext : receivedContext
        guard !context.isEmpty else { return }
        if let value = context["isOnDuty"] as? Bool {
            isOnDuty = value
        }
        applyStatePayload(context)
    }

    private func shouldApplyState(lastUpdatedAtSeconds: TimeInterval?) -> Bool {
        let defaults = UserDefaults.standard
        let lastApplied = defaults.double(forKey: SyncOrderKey.lastAppliedAt)
        guard let lastUpdatedAtSeconds else {
            if lastApplied > 0 {
                print("WCSession ignored state missing lastUpdatedAt")
                return false
            }
            return true
        }
        if lastApplied > 0, lastUpdatedAtSeconds <= lastApplied {
            print("WCSession ignored out-of-order state lastUpdated=\(lastUpdatedAtSeconds) lastApplied=\(lastApplied)")
            return false
        }
        defaults.set(lastUpdatedAtSeconds, forKey: SyncOrderKey.lastAppliedAt)
#if DEBUG
        debugLastAppliedAt = formatDebugTimestamp(lastUpdatedAtSeconds)
#endif
        return true
    }

    private func normalizedStage(_ value: String?) -> String {
        switch value {
        case WidgetStateStore.stageShooting, WidgetStateStore.stageSelecting, WidgetStateStore.stageStopped:
            return value ?? WidgetStateStore.stageStopped
        default:
            return WidgetStateStore.stageStopped
        }
    }

    private func parseEpoch(_ value: Any?) -> TimeInterval? {
        if let seconds = value as? Double {
            return seconds
        }
        if let seconds = value as? Int {
            return TimeInterval(seconds)
        }
        return nil
    }

#if DEBUG
    private func formatDebugTimestamp(_ seconds: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm:ss"
        return "\(Int(seconds)) (\(formatter.string(from: date)))"
    }
#endif
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

        var id: String {
            switch self {
            case .notOnDuty:
                return "notOnDuty"
            }
        }

        var message: String {
            switch self {
            case .notOnDuty:
                return "未上班，无法开始记录"
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

        VStack(spacing: 10) {
            VStack(spacing: 4) {
                if syncStore.isOnDuty {
                    Text(stageLabel)
                        .font(.headline)
                } else {
                    Text("未上班，无法开始记录")
                        .font(.headline)
                }
                Text("总时长 \(format(durations.total)) · 当前阶段 \(format(durations.currentStage))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
#if DEBUG
            .contentShape(Rectangle())
            .onTapGesture(count: 5) {
                showDebugPanel.toggle()
            }
#endif

            Button(action: handlePrimaryAction) {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

#if DEBUG
            if showDebugPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("lastReceivedPayload")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(syncStore.debugLastReceivedPayload)
                        .font(.caption2)

                    Text("lastAppliedAt")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(syncStore.debugLastAppliedAt)
                        .font(.caption2)

                    Text("sessionStatus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(syncStore.debugSessionStatus)
                        .font(.caption2)
                }
                .padding(6)
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
        .onReceive(syncStore.$incomingState) { state in
            guard let state else { return }
            applyIncomingState(state)
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
            syncStore.sendSessionEvent(event: "startShooting", timestamp: now.timeIntervalSince1970)
            updateWidgetState(isRunning: true, startedAt: now, stage: WidgetStateStore.stageShooting)
        case .shooting:
            stage = .selecting
            session.selectingStart = now
            syncStore.sendSessionEvent(event: "startSelecting", timestamp: now.timeIntervalSince1970)
            updateWidgetState(isRunning: true, startedAt: session.shootingStart, stage: WidgetStateStore.stageSelecting)
        case .selecting:
            stage = .ended
            session.endedAt = now
            syncStore.sendSessionEvent(event: "end", timestamp: now.timeIntervalSince1970)
            updateWidgetState(isRunning: false, startedAt: nil, stage: WidgetStateStore.stageStopped)
        case .ended:
            session = Session()
            session.shootingStart = now
            stage = .shooting
            syncStore.sendSessionEvent(event: "startShooting", timestamp: now.timeIntervalSince1970)
            updateWidgetState(isRunning: true, startedAt: now, stage: WidgetStateStore.stageShooting)
        }
    }

    private func resetSession() {
        stage = .idle
        session = Session()
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

    private func updateWidgetState(isRunning: Bool, startedAt: Date?, stage: String, lastUpdatedAt: Date = Date()) {
        WidgetStateStore.writeState(
            isRunning: isRunning,
            startedAt: startedAt,
            stage: stage,
            lastUpdatedAt: lastUpdatedAt
        )
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStateStore.widgetKind)
    }

    @MainActor
    private func applyIncomingState(_ state: WatchSyncStore.IncomingState) {
        let stageValue = state.stage
        switch stageValue {
        case WidgetStateStore.stageShooting:
            stage = .shooting
            session.shootingStart = state.startedAt ?? state.lastUpdatedAt
            session.selectingStart = nil
            session.endedAt = nil
        case WidgetStateStore.stageSelecting:
            stage = .selecting
            session.shootingStart = state.startedAt ?? state.lastUpdatedAt
            session.selectingStart = state.lastUpdatedAt
            session.endedAt = nil
        default:
            if let startedAt = state.startedAt {
                stage = .ended
                session.shootingStart = startedAt
                session.selectingStart = nil
                session.endedAt = state.lastUpdatedAt
            } else {
                stage = .idle
                session = Session()
            }
        }

        updateWidgetState(
            isRunning: state.isRunning,
            startedAt: state.startedAt,
            stage: stageValue,
            lastUpdatedAt: state.lastUpdatedAt
        )
        print("Applied watch state stage=\(stageValue)")
    }

}

#Preview {
    ContentView(syncStore: WatchSyncStore())
}
