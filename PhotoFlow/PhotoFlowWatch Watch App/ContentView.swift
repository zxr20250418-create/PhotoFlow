//
//  ContentView.swift
//  PhotoFlowWatch Watch App
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import Combine
import SwiftUI
#if os(watchOS)
import WatchKit
#endif
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
        static let lastAppliedRevision = "pf_sync_lastAppliedRevision"
    }

    private enum CanonicalKey {
        static let type = "type"
        static let canonicalType = "canonical_state"
        static let requestType = "canonical_request"
        static let sessionId = "sessionId"
        static let stage = "stage"
        static let shootingStart = "shootingStart"
        static let selectingStart = "selectingStart"
        static let endedAt = "endedAt"
        static let updatedAt = "updatedAt"
        static let revision = "revision"
        static let sourceDevice = "sourceDevice"
    }

    struct CanonicalState: Equatable {
        let sessionId: String
        let stage: String
        let shootingStart: Date?
        let selectingStart: Date?
        let endedAt: Date?
        let updatedAt: Date
        let revision: Int64
        let sourceDevice: String
    }

    @Published var isOnDuty = false
    @Published var incomingState: CanonicalState?
    @Published var lastSyncAt: Date?
    @Published var sessionActivationState: WCSessionActivationState = .notActivated
    @Published var sessionReachable = false
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
        let session = WCSession.default
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("WCSession updateApplicationContext failed: \(error.localizedDescription)")
        }
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
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
        updateSessionStatus(for: session)
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
        updateSessionStatus(for: session)
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
        if let type = message[CanonicalKey.type] as? String, type == CanonicalKey.requestType {
            if let state = incomingState {
                sendCanonicalState(state)
            }
            return
        }
        applyStatePayload(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        applyStatePayload(userInfo)
    }

    private func applyStatePayload(_ payload: [String: Any]) {
        if let value = payload["isOnDuty"] as? Bool {
            isOnDuty = value
        }
        if let canonical = decodeCanonicalState(from: payload) {
            mergeCanonicalState(canonical)
            return
        }
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
        let resolvedLastUpdatedSeconds = lastUpdatedSeconds ?? Date().timeIntervalSince1970
        let revision = Int64(resolvedLastUpdatedSeconds * 1000)
        let state = CanonicalState(
            sessionId: "legacy",
            stage: stage,
            shootingStart: startedAtSeconds.map { Date(timeIntervalSince1970: $0) },
            selectingStart: nil,
            endedAt: isRunning ? nil : Date(timeIntervalSince1970: resolvedLastUpdatedSeconds),
            updatedAt: Date(timeIntervalSince1970: resolvedLastUpdatedSeconds),
            revision: revision,
            sourceDevice: payload[CanonicalKey.sourceDevice] as? String ?? "phone"
        )
        mergeCanonicalState(state)
    }

    private func updateSessionStatus(for session: WCSession) {
        sessionActivationState = session.activationState
        sessionReachable = session.isReachable
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

    func requestLatestState() {
        guard WCSession.isSupported() else { return }
        applyLatestContextIfAvailable(from: WCSession.default)
        let payload: [String: Any] = [
            CanonicalKey.type: CanonicalKey.requestType,
            CanonicalKey.sourceDevice: "watch"
        ]
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
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

    private func mergeCanonicalState(_ incoming: CanonicalState) {
        guard shouldApplyState(incoming) else { return }
        incomingState = incoming
        lastSyncAt = incoming.updatedAt
        UserDefaults.standard.set(incoming.revision, forKey: SyncOrderKey.lastAppliedRevision)
#if DEBUG
        debugLastAppliedAt = formatDebugTimestamp(TimeInterval(incoming.revision) / 1000)
#endif
    }

    private func shouldApplyState(_ incoming: CanonicalState) -> Bool {
        let defaults = UserDefaults.standard
        let lastApplied = defaults.object(forKey: SyncOrderKey.lastAppliedRevision) as? Int64 ?? 0
        if incoming.revision > lastApplied {
            return true
        }
        if incoming.revision < lastApplied {
            return false
        }
        return sourcePriority(incoming.sourceDevice) > sourcePriority(incomingState?.sourceDevice ?? "unknown")
    }

    private func sourcePriority(_ source: String) -> Int {
        switch source {
        case "phone":
            return 2
        case "watch":
            return 1
        default:
            return 0
        }
    }

    private func decodeCanonicalState(from payload: [String: Any]) -> CanonicalState? {
        let type = payload[CanonicalKey.type] as? String
        let hasCanonicalType = type == CanonicalKey.canonicalType
        let hasSessionId = payload[CanonicalKey.sessionId] != nil
        let hasStage = payload[CanonicalKey.stage] != nil
        guard hasCanonicalType || (hasSessionId && hasStage) else { return nil }
        guard let sessionId = parseString(payload[CanonicalKey.sessionId]) else { return nil }
        let stage = payload[CanonicalKey.stage] as? String ?? WidgetStateStore.stageStopped
        let revision = parseInt64(payload[CanonicalKey.revision]) ?? Int64(Date().timeIntervalSince1970 * 1000)
        let updatedSeconds = parseEpoch(payload[CanonicalKey.updatedAt]) ?? Date().timeIntervalSince1970
        return CanonicalState(
            sessionId: sessionId,
            stage: stage,
            shootingStart: parseEpoch(payload[CanonicalKey.shootingStart]).map { Date(timeIntervalSince1970: $0) },
            selectingStart: parseEpoch(payload[CanonicalKey.selectingStart]).map { Date(timeIntervalSince1970: $0) },
            endedAt: parseEpoch(payload[CanonicalKey.endedAt]).map { Date(timeIntervalSince1970: $0) },
            updatedAt: Date(timeIntervalSince1970: updatedSeconds),
            revision: revision,
            sourceDevice: payload[CanonicalKey.sourceDevice] as? String ?? "unknown"
        )
    }

    private func parseInt64(_ value: Any?) -> Int64? {
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

    private func parseString(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let string = value as? NSString {
            return string as String
        }
        return nil
    }

    func sendCanonicalState(_ state: CanonicalState) {
        guard WCSession.isSupported() else { return }
        var payload: [String: Any] = [
            CanonicalKey.type: CanonicalKey.canonicalType,
            CanonicalKey.sessionId: state.sessionId,
            CanonicalKey.stage: state.stage,
            CanonicalKey.updatedAt: state.updatedAt.timeIntervalSince1970,
            CanonicalKey.revision: state.revision,
            CanonicalKey.sourceDevice: state.sourceDevice
        ]
        if let shootingStart = state.shootingStart {
            payload[CanonicalKey.shootingStart] = shootingStart.timeIntervalSince1970
        }
        if let selectingStart = state.selectingStart {
            payload[CanonicalKey.selectingStart] = selectingStart.timeIntervalSince1970
        }
        if let endedAt = state.endedAt {
            payload[CanonicalKey.endedAt] = endedAt.timeIntervalSince1970
        }
        payload[WidgetStateStore.keyStage] = state.stage
        payload[WidgetStateStore.keyIsRunning] = state.stage != WidgetStateStore.stageStopped
        payload[WidgetStateStore.keyStartedAt] = state.shootingStart?.timeIntervalSince1970
        payload[WidgetStateStore.keyLastUpdatedAt] = state.updatedAt.timeIntervalSince1970

        let session = WCSession.default
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("WCSession updateApplicationContext failed: \(error.localizedDescription)")
        }
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
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
    @State private var sessionId: String?
    @State private var activeAlert: ActiveAlert?
    @State private var now = Date()
#if os(watchOS)
    @Environment(\.scenePhase) private var scenePhase
#endif
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
            Text(syncStore.isOnDuty ? stageLabel : "未上班")
                .font(.title3)
                .fontWeight(.semibold)
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
            .contextMenu {
                Button("立即同步") {
                    syncStore.requestLatestState()
                }
                if syncStore.isOnDuty {
                    Button("下班", role: .destructive) {
                        setOnDuty(false)
                    }
                }
                Button("补记最近一单") { }
                    .disabled(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("总时长 \(format(durations.total))")
                Text("当前阶段 \(format(durations.currentStage))")
                Text("最近同步 \(formatSyncTime(syncStore.lastSyncAt))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .task {
            syncStore.requestLatestState()
        }
        .onReceive(syncStore.$incomingState) { state in
            guard let state else { return }
            applyIncomingState(state)
        }
#if os(watchOS)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                syncStore.requestLatestState()
            }
        }
#endif
    }

    private var stageLabel: String {
        switch stage {
        case .idle:
            return "待开始"
        case .shooting:
            return "拍摄"
        case .selecting:
            return "选片"
        case .ended:
            return "已结束"
        }
    }

    private var connectionStatusText: String {
        guard syncStore.sessionActivationState == .activated else {
            return "未连接"
        }
        return syncStore.sessionReachable ? "已连接" : "未连接"
    }

    private var primaryButtonTitle: String {
        if !syncStore.isOnDuty {
            return "上班"
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
            setOnDuty(true)
            return
        }
        let now = Date()
        switch stage {
        case .idle:
            stage = .shooting
            session.shootingStart = now
            sessionId = makeSessionId(startedAt: now)
            let state = makeCanonicalState(stage: WidgetStateStore.stageShooting, now: now)
            syncStore.sendCanonicalState(state)
            updateWidgetState(isRunning: true, startedAt: now, stage: WidgetStateStore.stageShooting)
            playStageHaptic()
        case .shooting:
            stage = .selecting
            session.selectingStart = now
            let state = makeCanonicalState(stage: WidgetStateStore.stageSelecting, now: now)
            syncStore.sendCanonicalState(state)
            updateWidgetState(isRunning: true, startedAt: session.shootingStart, stage: WidgetStateStore.stageSelecting)
            playStageHaptic()
        case .selecting:
            stage = .ended
            session.endedAt = now
            let state = makeCanonicalState(stage: WidgetStateStore.stageStopped, now: now)
            syncStore.sendCanonicalState(state)
            updateWidgetState(isRunning: false, startedAt: nil, stage: WidgetStateStore.stageStopped)
            playStageHaptic()
        case .ended:
            session = Session()
            session.shootingStart = now
            stage = .shooting
            sessionId = makeSessionId(startedAt: now)
            let state = makeCanonicalState(stage: WidgetStateStore.stageShooting, now: now)
            syncStore.sendCanonicalState(state)
            updateWidgetState(isRunning: true, startedAt: now, stage: WidgetStateStore.stageShooting)
            playStageHaptic()
        }
    }

    private func resetSession() {
        stage = .idle
        session = Session()
        sessionId = nil
    }

    private func setOnDuty(_ value: Bool) {
        syncStore.setOnDuty(value)
        if value {
            syncStore.requestLatestState()
        } else {
            resetSession()
        }
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

    private func playStageHaptic() {
#if os(watchOS)
        WKInterfaceDevice.current().play(.click)
#endif
    }

    private func updateWidgetState(isRunning: Bool, startedAt: Date?, stage: String, lastUpdatedAt: Date = Date()) {
        let resolvedStartedAt = isRunning ? (startedAt ?? Date()) : startedAt
        WidgetStateStore.writeState(
            isRunning: isRunning,
            startedAt: resolvedStartedAt,
            stage: stage,
            lastUpdatedAt: lastUpdatedAt
        )
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStateStore.widgetKind)
    }

    @MainActor
    private func applyIncomingState(_ state: WatchSyncStore.CanonicalState) {
        let stageValue = state.stage
        sessionId = state.sessionId
        switch stageValue {
        case WidgetStateStore.stageShooting:
            stage = .shooting
            session.shootingStart = state.shootingStart ?? state.updatedAt
            session.selectingStart = nil
            session.endedAt = nil
        case WidgetStateStore.stageSelecting:
            stage = .selecting
            session.shootingStart = state.shootingStart ?? state.updatedAt
            session.selectingStart = state.selectingStart ?? state.updatedAt
            session.endedAt = nil
        default:
            if let startedAt = state.shootingStart ?? state.endedAt {
                stage = .ended
                session.shootingStart = startedAt
                session.selectingStart = state.selectingStart
                session.endedAt = state.endedAt ?? state.updatedAt
            } else {
                stage = .idle
                session = Session()
                sessionId = nil
            }
        }

        updateWidgetState(
            isRunning: stageValue != WidgetStateStore.stageStopped,
            startedAt: state.shootingStart,
            stage: stageValue,
            lastUpdatedAt: state.updatedAt
        )
        print("Applied watch state stage=\(stageValue)")
    }

    private func makeSessionId(startedAt: Date) -> String {
        "session-\(Int(startedAt.timeIntervalSince1970 * 1000))"
    }

    private func makeCanonicalState(stage: String, now: Date) -> WatchSyncStore.CanonicalState {
        let baseTime = session.shootingStart ?? session.selectingStart ?? session.endedAt ?? now
        let resolvedSessionId = sessionId ?? makeSessionId(startedAt: baseTime)
        return WatchSyncStore.CanonicalState(
            sessionId: resolvedSessionId,
            stage: stage,
            shootingStart: session.shootingStart,
            selectingStart: session.selectingStart,
            endedAt: session.endedAt,
            updatedAt: now,
            revision: Int64(now.timeIntervalSince1970 * 1000),
            sourceDevice: "watch"
        )
    }

}

#Preview {
    ContentView(syncStore: WatchSyncStore())
}
