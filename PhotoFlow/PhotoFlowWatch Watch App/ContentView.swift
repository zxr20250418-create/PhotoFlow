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

    private enum EventKey {
        static let type = "type"
        static let eventType = "session_event"
        static let eventId = "eventId"
        static let sessionId = "sessionId"
        static let action = "action"
        static let clientAt = "clientAt"
        static let sourceDevice = "sourceDevice"
        static let ackForEventId = "ackForEventId"
    }

    private enum OutboxKey {
        static let storage = "pf_watch_event_outbox_v1"
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

    struct SyncEvent: Codable, Equatable, Identifiable {
        let id: String
        let sessionId: String
        let action: String
        let clientAt: TimeInterval
        let sourceDevice: String
        var queuedAt: TimeInterval
        var lastAttemptAt: TimeInterval?
    }

    @Published var isOnDuty = false
    @Published var incomingState: CanonicalState?
    @Published var lastSyncAt: Date?
    @Published var pendingCount: Int = 0
    @Published var lastRevision: Int64 = 0
    @Published var sessionActivationState: WCSessionActivationState = .notActivated
    @Published var sessionReachable = false
#if DEBUG
    @Published var debugLastReceivedPayload: String = "—"
    @Published var debugLastAppliedAt: String = "—"
    @Published var debugSessionStatus: String = "—"
#endif
    private var outbox: [SyncEvent] = []
    private var pendingEventIds: Set<String> = []

    override init() {
        super.init()
        loadOutbox()
        pendingEventIds = Set(outbox.map(\.id))
        pendingCount = pendingEventIds.count
        lastRevision = UserDefaults.standard.object(forKey: SyncOrderKey.lastAppliedRevision) as? Int64 ?? 0
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        if session.activationState == .activated {
            applyLatestContextIfAvailable(from: session)
            flushOutbox()
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

    func sendSessionEvent(action: String, sessionId: String, clientAt: Date) {
        let event = SyncEvent(
            id: UUID().uuidString,
            sessionId: sessionId,
            action: action,
            clientAt: clientAt.timeIntervalSince1970,
            sourceDevice: "watch",
            queuedAt: Date().timeIntervalSince1970,
            lastAttemptAt: nil
        )
        enqueueEvent(event)
        sendEvent(event)
        schedulePendingTimeout(for: event.id)
    }

    private func enqueueEvent(_ event: SyncEvent) {
        guard !outbox.contains(where: { $0.id == event.id }) else { return }
        outbox.append(event)
        saveOutbox()
    }

    private func sendEvent(_ event: SyncEvent) {
        guard WCSession.isSupported() else { return }
        markAttempt(for: event.id)
        let payload = encodeEvent(event)
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self] reply in
                self?.applyStatePayload(reply)
            }, errorHandler: { _ in
                session.transferUserInfo(payload)
            })
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func flushOutbox() {
        guard WCSession.isSupported(), !outbox.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        for event in outbox {
            if let lastAttemptAt = event.lastAttemptAt, now - lastAttemptAt < 2 {
                continue
            }
            sendEvent(event)
        }
    }

    private func schedulePendingTimeout(for eventId: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            guard self.outbox.contains(where: { $0.id == eventId }) else { return }
            self.pendingEventIds.insert(eventId)
            self.pendingCount = self.pendingEventIds.count
        }
    }

    private func clearEvent(_ eventId: String) {
        outbox.removeAll { $0.id == eventId }
        pendingEventIds.remove(eventId)
        pendingCount = pendingEventIds.count
        saveOutbox()
    }

    private func markAttempt(for eventId: String) {
        guard let index = outbox.firstIndex(where: { $0.id == eventId }) else { return }
        outbox[index].lastAttemptAt = Date().timeIntervalSince1970
        saveOutbox()
    }

    private func encodeEvent(_ event: SyncEvent) -> [String: Any] {
        [
            EventKey.type: EventKey.eventType,
            EventKey.eventId: event.id,
            EventKey.sessionId: event.sessionId,
            EventKey.action: event.action,
            EventKey.clientAt: event.clientAt,
            EventKey.sourceDevice: event.sourceDevice
        ]
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard error == nil, activationState == .activated else { return }
        applyLatestContextIfAvailable(from: session)
        flushOutbox()
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
        if session.isReachable {
            flushOutbox()
        }
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
        if let ackId = parseString(payload[EventKey.ackForEventId]) {
            clearEvent(ackId)
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
        flushOutbox()
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
        lastRevision = incoming.revision
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

    private func loadOutbox() {
        guard let data = UserDefaults.standard.data(forKey: OutboxKey.storage),
              let decoded = try? JSONDecoder().decode([SyncEvent].self, from: data) else {
            return
        }
        outbox = decoded
    }

    private func saveOutbox() {
        guard let data = try? JSONEncoder().encode(outbox) else { return }
        UserDefaults.standard.set(data, forKey: OutboxKey.storage)
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
                if syncStore.pendingCount > 0 {
                    Text("待确认")
                        .opacity(0.4)
                }
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

                    Text("lastSyncAt / pending / lastRevision")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(formatSyncTime(syncStore.lastSyncAt)) · \(syncStore.pendingCount) · \(syncStore.lastRevision)")
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
            let resolvedSessionId = makeSessionId(startedAt: now)
            sessionId = resolvedSessionId
            syncStore.sendSessionEvent(action: "startShooting", sessionId: resolvedSessionId, clientAt: now)
            updateWidgetState(isRunning: true, startedAt: now, stage: WidgetStateStore.stageShooting)
            playStageHaptic()
        case .shooting:
            stage = .selecting
            session.selectingStart = now
            let resolvedSessionId = sessionId ?? makeSessionId(startedAt: session.shootingStart ?? now)
            sessionId = resolvedSessionId
            syncStore.sendSessionEvent(action: "startSelecting", sessionId: resolvedSessionId, clientAt: now)
            updateWidgetState(isRunning: true, startedAt: session.selectingStart, stage: WidgetStateStore.stageSelecting)
            playStageHaptic()
        case .selecting:
            stage = .ended
            session.endedAt = now
            let resolvedSessionId = sessionId ?? makeSessionId(startedAt: session.shootingStart ?? now)
            sessionId = resolvedSessionId
            syncStore.sendSessionEvent(action: "end", sessionId: resolvedSessionId, clientAt: now)
            updateWidgetState(isRunning: false, startedAt: nil, stage: WidgetStateStore.stageStopped)
            playStageHaptic()
        case .ended:
            session = Session()
            session.shootingStart = now
            stage = .shooting
            let resolvedSessionId = makeSessionId(startedAt: now)
            sessionId = resolvedSessionId
            syncStore.sendSessionEvent(action: "startShooting", sessionId: resolvedSessionId, clientAt: now)
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
        WidgetCenter.shared.reloadAllTimelines()
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

        let stageStartAt: Date?
        switch stageValue {
        case WidgetStateStore.stageSelecting:
            stageStartAt = session.selectingStart
        case WidgetStateStore.stageShooting:
            stageStartAt = session.shootingStart
        default:
            stageStartAt = nil
        }
        updateWidgetState(
            isRunning: stageValue != WidgetStateStore.stageStopped,
            startedAt: stageStartAt,
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
