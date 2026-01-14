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

struct SessionMeta: Codable, Equatable {
    var amountCents: Int?
    var shotCount: Int?
    var selectedCount: Int?

    var isEmpty: Bool {
        amountCents == nil && shotCount == nil && selectedCount == nil
    }
}

@MainActor
final class SessionMetaStore: ObservableObject {
    @Published private(set) var metas: [String: SessionMeta] = [:]
    private let storageKey = "pf_session_meta_v1"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func meta(for id: String) -> SessionMeta {
        metas[id] ?? SessionMeta()
    }

    func update(_ meta: SessionMeta, for id: String) {
        if meta.isEmpty {
            metas.removeValue(forKey: id)
        } else {
            metas[id] = meta
        }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: SessionMeta].self, from: data) else {
            return
        }
        metas = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(metas) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct ContentView: View {
    enum Stage {
        case idle
        case shooting
        case selecting
        case ended
    }

    enum Tab {
        case home
        case stats
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

    struct EditingSession: Identifiable {
        let id: String
    }

    private enum StatsRange: String, CaseIterable {
        case today
        case week
        case month

        var title: String {
            switch self {
            case .today:
                return "今日"
            case .week:
                return "本周"
            case .month:
                return "本月"
            }
        }
    }

    @State private var stage: Stage = .idle
    @State private var session = Session()
    @State private var activeAlert: ActiveAlert?
    @State private var now = Date()
    @State private var selectedTab: Tab = .home
    @State private var sessionSummaries: [SessionSummary] = []
    @StateObject private var metaStore: SessionMetaStore
    @State private var editingSession: EditingSession?
    @State private var draftAmount = ""
    @State private var draftShotCount = ""
    @State private var draftSelected = ""
    @State private var lastPromptedSessionId: String?
    @State private var statsRange: StatsRange = .today
#if DEBUG
    @State private var showDebugPanel = false
#endif
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @ObservedObject var syncStore: WatchSyncStore

    init(syncStore: WatchSyncStore) {
        self.syncStore = syncStore
        _metaStore = StateObject(wrappedValue: SessionMetaStore())
    }

    var body: some View {
        ZStack {
            if selectedTab == .home {
                homeView
            } else {
                statsView
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .alert(item: $activeAlert) { alert in
            Alert(title: Text(alert.message))
        }
        .sheet(item: $editingSession) { session in
            NavigationStack {
                Form {
                    Section {
                        TextField("金额", text: $draftAmount)
                            .keyboardType(.decimalPad)
                        TextField("拍摄张数", text: $draftShotCount)
                            .keyboardType(.numberPad)
                        TextField("选片张数", text: $draftSelected)
                            .keyboardType(.numberPad)
                    }
                }
                .navigationTitle("编辑指标")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            editingSession = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveMeta(for: session.id)
                            editingSession = nil
                        }
                    }
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .onReceive(syncStore.$incomingEvent) { event in
            guard let event = event else { return }
            applySessionEvent(event)
        }
    }

    private var homeView: some View {
        return VStack(spacing: 16) {
            Button(syncStore.isOnDuty ? "下班" : "上班") {
                let nextOnDuty = !syncStore.isOnDuty
                syncStore.setOnDuty(nextOnDuty)
                if !nextOnDuty {
                    resetSession()
                }
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 8) {
                Text("会话时间线")
                    .font(.headline)
                if sessionSummaries.isEmpty {
                    Text("暂无记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let displaySessions = Array(sessionSummaries.reversed())
                    ForEach(Array(displaySessions.enumerated()), id: \.element.id) { displayIndex, summary in
                        let total = displaySessions.count
                        let order = total - displayIndex
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("第\(order)单")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer(minLength: 8)
                                if let startTime = summary.shootingStart ?? sessionStartTime(for: summary) {
                                    Text(formatTimelineTime(startTime))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Button(action: { startEditingMeta(for: summary.id) }) {
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            Text(sessionDurationSummary(for: summary))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                            if let metaText = metaSummary(for: summary.id) {
                                Text(metaText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var statsView: some View {
        let isoCal = Calendar(identifier: .iso8601)
        let filteredSessions = sessionSummaries.filter { summary in
            guard let shootingStart = summary.shootingStart else { return false }
            switch statsRange {
            case .today:
                return isoCal.isDateInToday(shootingStart)
            case .week:
                guard let interval = isoCal.dateInterval(of: .weekOfYear, for: now) else { return false }
                return interval.contains(shootingStart)
            case .month:
                guard let interval = isoCal.dateInterval(of: .month, for: now) else { return false }
                return interval.contains(shootingStart)
            }
        }
        let totals = filteredSessions.reduce(into: (total: TimeInterval(0), shooting: TimeInterval(0), selecting: TimeInterval(0))) { result, summary in
            let durations = sessionDurations(for: summary)
            result.total += durations.total
            result.shooting += durations.shooting
            if let selecting = durations.selecting {
                result.selecting += selecting
            }
        }
        let count = filteredSessions.count
        let avgTotal = count > 0 ? totals.total / Double(count) : nil
        let selectShare = totals.total > 0 ? totals.selecting / totals.total : nil
        let prefix = statsRange.title
        let avgText = avgTotal.map { format($0) } ?? "--"
        let shareText = selectShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "--"
        return VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $statsRange) {
                ForEach(StatsRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Text("\(prefix)单数 \(count)")
            Text("\(prefix)总时长 \(format(totals.total))")
            Text("\(prefix)拍摄时长 \(format(totals.shooting))")
            Text("\(prefix)选片时长 \(format(totals.selecting))")
            Text("\(prefix)平均每单总时长 \(avgText)")
            Text("\(prefix)选片占比 \(shareText)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private var bottomBar: some View {
        return HStack(alignment: .bottom, spacing: 16) {
            bottomTabButton(title: "Home", systemImage: "house", tab: .home)
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Text(syncStore.isOnDuty ? stageLabel : "未上班")
                    .font(.headline)
                nextActionButton
            }
            Spacer(minLength: 0)
            bottomTabButton(title: "Stats", systemImage: "chart.bar", tab: .stats)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func bottomTabButton(title: String, systemImage: String, tab: Tab) -> some View {
        Button(action: { selectedTab = tab }) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption2)
            .frame(minWidth: 44)
        }
        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
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

    private var nextActionTitle: String {
        switch stage {
        case .idle, .ended:
            return "拍摄"
        case .shooting:
            return "选片"
        case .selecting:
            return "结束"
        }
    }

    private var nextActionButton: some View {
        let durations = computeDurations(now: now)
        return Button(action: performNextAction) {
            VStack(spacing: 2) {
                Text(nextActionTitle)
                    .font(.headline)
                Text("总 \(format(durations.total)) · 阶段 \(format(durations.currentStage))")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(minWidth: 96)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .contextMenu {
            Button("拍摄") { performStageAction(.shooting) }
                .disabled(!canStartShooting)
            Button("选片") { performStageAction(.selecting) }
                .disabled(!canStartSelecting)
            Button("结束") { performStageAction(.ended) }
                .disabled(!canEndSession)
        }
    }

    private var canStartShooting: Bool {
        stage == .idle || stage == .ended
    }

    private var canStartSelecting: Bool {
        stage == .shooting
    }

    private var canEndSession: Bool {
        stage == .shooting || stage == .selecting
    }

    private func resetSession() {
        endActiveSessionIfNeeded(at: Date())
        stage = .idle
        session = Session()
        syncStageState(now: Date())
    }

    private func performNextAction() {
        let targetStage: Stage
        switch stage {
        case .idle, .ended:
            targetStage = .shooting
        case .shooting:
            targetStage = .selecting
        case .selecting:
            targetStage = .ended
        }
        performStageAction(targetStage)
    }

    private func performStageAction(_ targetStage: Stage) {
        guard syncStore.isOnDuty else {
            activeAlert = .notOnDuty
            return
        }
        let now = Date()
        let endedSessionId = targetStage == .ended ? activeSessionIndex().map { sessionSummaries[$0].id } : nil
        switch targetStage {
        case .shooting:
            session = Session()
            session.shootingStart = now
            stage = .shooting
        case .selecting:
            session.shootingStart = session.shootingStart ?? now
            session.selectingStart = now
            stage = .selecting
        case .ended:
            session.endedAt = now
            stage = .ended
        case .idle:
            break
        }
        updateSessionSummary(for: targetStage, at: now)
        if targetStage == .ended {
            let sessionId = endedSessionId ?? sessionIdForTimestamp(now)
            if let sessionId {
                promptSettlementIfNeeded(for: sessionId)
            }
        }
        syncStageState(now: now)
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
            let endedSessionId = activeSessionIndex().map { sessionSummaries[$0].id }
            updateSessionSummary(for: .ended, at: timestamp)
            if let sessionId = endedSessionId ?? sessionIdForTimestamp(timestamp) {
                promptSettlementIfNeeded(for: sessionId)
            }
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

    private func sessionIdForTimestamp(_ timestamp: Date) -> String? {
        guard let index = targetSessionIndex(for: timestamp) else { return nil }
        return sessionSummaries[index].id
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

    private func sessionDurationSummary(for summary: SessionSummary) -> String {
        let durations = sessionDurations(for: summary)
        var parts = [
            "总 \(format(durations.total))",
            "拍 \(format(durations.shooting))"
        ]
        if let selecting = durations.selecting {
            parts.append("选 \(format(selecting))")
        }
        return parts.joined(separator: "  ")
    }

    private func startEditingMeta(for sessionId: String) {
        let meta = metaStore.meta(for: sessionId)
        draftAmount = meta.amountCents.map(amountText(from:)) ?? ""
        draftShotCount = meta.shotCount.map(String.init) ?? ""
        draftSelected = meta.selectedCount.map(String.init) ?? ""
        editingSession = EditingSession(id: sessionId)
    }

    private func saveMeta(for sessionId: String) {
        let meta = SessionMeta(
            amountCents: parseAmountCents(from: draftAmount),
            shotCount: parseInt(from: draftShotCount),
            selectedCount: parseInt(from: draftSelected)
        )
        metaStore.update(meta, for: sessionId)
    }

    private func promptSettlementIfNeeded(for sessionId: String) {
        guard lastPromptedSessionId != sessionId else { return }
        lastPromptedSessionId = sessionId
        startEditingMeta(for: sessionId)
    }

    private func metaSummary(for sessionId: String) -> String? {
        let meta = metaStore.meta(for: sessionId)
        var parts: [String] = []
        if let amountCents = meta.amountCents {
            parts.append(formatAmount(cents: amountCents))
        }
        if let shot = meta.shotCount {
            parts.append("拍\(shot)张")
        }
        if let selected = meta.selectedCount {
            parts.append("选\(selected)张")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatAmount(cents: Int) -> String {
        if cents % 100 == 0 {
            return "¥\(cents / 100)"
        }
        let value = Double(cents) / 100
        return String(format: "¥%.2f", value)
    }

    private func amountText(from cents: Int) -> String {
        if cents % 100 == 0 {
            return "\(cents / 100)"
        }
        let value = Double(cents) / 100
        return String(format: "%.2f", value)
    }

    private func parseAmountCents(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized) else { return nil }
        return Int((value * 100).rounded())
    }

    private func parseInt(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed), value >= 0 else { return nil }
        return value
    }

    private func sessionDurations(for summary: SessionSummary) -> (total: TimeInterval, shooting: TimeInterval, selecting: TimeInterval?) {
        guard let shootingStart = summary.shootingStart else {
            return (0, 0, nil)
        }
        let endTime = summary.endedAt ?? now
        let total = max(0, endTime.timeIntervalSince(shootingStart))

        let shooting: TimeInterval
        if let selectingStart = summary.selectingStart {
            shooting = max(0, selectingStart.timeIntervalSince(shootingStart))
        } else if let endedAt = summary.endedAt {
            shooting = max(0, endedAt.timeIntervalSince(shootingStart))
        } else {
            shooting = max(0, now.timeIntervalSince(shootingStart))
        }

        let selecting: TimeInterval?
        if let selectingStart = summary.selectingStart {
            let selectingEnd = summary.endedAt ?? now
            selecting = max(0, selectingEnd.timeIntervalSince(selectingStart))
        } else {
            selecting = nil
        }

        return (total, shooting, selecting)
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
