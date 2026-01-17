//
//  ContentView.swift
//  PhotoFlow
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import Combine
import SwiftUI
import UIKit
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
    var reviewNote: String?

    var isEmpty: Bool {
        amountCents == nil && shotCount == nil && selectedCount == nil && reviewNote == nil
    }
}

struct SessionTimeOverride: Codable, Equatable {
    var shootingStart: Date
    var selectingStart: Date?
    var endedAt: Date?
    var updatedAt: Date
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

@MainActor
final class SessionTimeOverrideStore: ObservableObject {
    @Published private(set) var overrides: [String: SessionTimeOverride] = [:]
    private let storageKey = "pf_session_time_overrides_v1"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func override(for id: String) -> SessionTimeOverride? {
        overrides[id]
    }

    func update(_ overrideValue: SessionTimeOverride, for id: String) {
        overrides[id] = overrideValue
        save()
    }

    func clear(for id: String) {
        overrides.removeValue(forKey: id)
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: SessionTimeOverride].self, from: data) else {
            return
        }
        overrides = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct ManualSession: Codable, Equatable, Identifiable {
    let id: String
    var shootingStart: Date
    var selectingStart: Date?
    var endedAt: Date
}

@MainActor
final class ManualSessionStore: ObservableObject {
    @Published private(set) var sessions: [String: ManualSession] = [:]
    private let storageKey = "pf_manual_sessions_v1"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func upsert(_ session: ManualSession) {
        sessions[session.id] = session
        save()
    }

    func session(for id: String) -> ManualSession? {
        sessions[id]
    }

    func remove(_ id: String) {
        sessions.removeValue(forKey: id)
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ManualSession].self, from: data) else {
            return
        }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct ShiftRecord: Codable, Equatable {
    var startAt: Date?
    var endAt: Date?

    var isEmpty: Bool {
        startAt == nil && endAt == nil
    }
}

@MainActor
final class ShiftRecordStore: ObservableObject {
    @Published private(set) var records: [String: ShiftRecord] = [:]
    private let storageKey = "pf_shift_records_v1"
    private let defaults = UserDefaults.standard
    private let calendar: Calendar
    private let formatter: DateFormatter

    init() {
        calendar = Calendar(identifier: .iso8601)
        formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        load()
    }

    func dayKey(for date: Date) -> String {
        formatter.string(from: date)
    }

    func record(for key: String) -> ShiftRecord? {
        records[key]
    }

    func upsert(_ record: ShiftRecord, for key: String) {
        if record.isEmpty {
            records.removeValue(forKey: key)
        } else {
            records[key] = record
        }
        save()
    }

    func setStartIfNeeded(_ start: Date, for key: String) {
        var record = records[key] ?? ShiftRecord()
        if record.startAt == nil {
            record.startAt = start
        }
        record.endAt = nil
        upsert(record, for: key)
    }

    func setEnd(_ end: Date, for key: String) {
        var record = records[key] ?? ShiftRecord()
        record.endAt = end
        upsert(record, for: key)
    }

    func seedFromLegacy(start: Date?, end: Date?) {
        guard let start else { return }
        let key = dayKey(for: start)
        var record = records[key] ?? ShiftRecord()
        if record.startAt == nil {
            record.startAt = start
        }
        if let end {
            record.endAt = end
        }
        upsert(record, for: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: ShiftRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

@MainActor
final class DailyMemoStore: ObservableObject {
    @Published private(set) var memos: [String: String] = [:]
    private let storageKey = "pf_daily_memos_v1"
    private let defaults = UserDefaults.standard
    private let formatter: DateFormatter

    init() {
        let calendar = Calendar(identifier: .iso8601)
        formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        load()
    }

    func dayKey(for date: Date) -> String {
        formatter.string(from: date)
    }

    func memo(for key: String) -> String {
        memos[key] ?? ""
    }

    func setMemo(_ memo: String, for key: String) {
        let trimmed = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            memos.removeValue(forKey: key)
        } else {
            memos[key] = memo
        }
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        memos = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(memos) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

@MainActor
final class SessionVisibilityStore: ObservableObject {
    @Published private(set) var voidedIds: Set<String> = []
    @Published private(set) var deletedIds: Set<String> = []
    private let voidedKey = "pf_session_voided_v1"
    private let deletedKey = "pf_session_deleted_v1"
    private let defaults = UserDefaults.standard

    init() {
        load()
    }

    func isVoided(_ id: String) -> Bool {
        voidedIds.contains(id)
    }

    func isDeleted(_ id: String) -> Bool {
        deletedIds.contains(id)
    }

    func setVoided(_ id: String, isVoided: Bool) {
        guard !deletedIds.contains(id) else { return }
        if isVoided {
            voidedIds.insert(id)
        } else {
            voidedIds.remove(id)
        }
        save()
    }

    func markDeleted(_ id: String) {
        deletedIds.insert(id)
        voidedIds.remove(id)
        save()
    }

    private func load() {
        if let data = defaults.data(forKey: voidedKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            voidedIds = Set(decoded)
        }
        if let data = defaults.data(forKey: deletedKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            deletedIds = Set(decoded)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Array(voidedIds)) {
            defaults.set(data, forKey: voidedKey)
        }
        if let data = try? JSONEncoder().encode(Array(deletedIds)) {
            defaults.set(data, forKey: deletedKey)
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

    struct SessionTimes {
        var shootingStart: Date?
        var selectingStart: Date?
        var endedAt: Date?
    }

    struct DataQualityItem: Identifiable {
        let id = UUID()
        let summary: SessionSummary
        let text: String
    }

    enum ActiveAlert: Identifiable {
        case notOnDuty
        case cannotEndWhileShooting
        case validation(String)

        var id: String {
            switch self {
            case .notOnDuty:
                return "notOnDuty"
            case .cannotEndWhileShooting:
                return "cannotEndWhileShooting"
            case .validation(let message):
                return "validation-\(message)"
            }
        }

        var message: String {
            switch self {
            case .notOnDuty:
                return "未上班，无法开始记录"
            case .cannotEndWhileShooting:
                return "拍摄中不可直接结束"
            case .validation(let message):
                return message
            }
        }
    }

    struct EditingSession: Identifiable {
        let id: String
    }

    struct TimeEditingSession: Identifiable {
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
    @StateObject private var timeOverrideStore: SessionTimeOverrideStore
    @StateObject private var manualSessionStore: ManualSessionStore
    @StateObject private var shiftRecordStore: ShiftRecordStore
    @StateObject private var dailyMemoStore: DailyMemoStore
    @StateObject private var sessionVisibilityStore: SessionVisibilityStore
    @State private var editingSession: EditingSession?
    @State private var timeEditingSession: TimeEditingSession?
    @State private var deleteCandidateId: String?
    @State private var memoDraft = ""
    @State private var draftAmount = ""
    @State private var draftShotCount = ""
    @State private var draftSelected = ""
    @State private var draftReviewNote = ""
    @State private var draftManualShootingStart = Date()
    @State private var draftManualSelectingStart = Date()
    @State private var draftManualEndedAt = Date()
    @State private var draftManualSelectingEnabled = false
    @State private var draftManualAmount = ""
    @State private var draftManualShotCount = ""
    @State private var draftManualSelectedCount = ""
    @State private var draftManualReviewNote = ""
    @State private var isManualSessionPresented = false
    @State private var draftOverrideShootingStart = Date()
    @State private var draftOverrideSelectingStart = Date()
    @State private var draftOverrideEndedAt = Date()
    @State private var draftOverrideSelectingEnabled = false
    @State private var draftOverrideEndedEnabled = false
    @State private var lastPromptedSessionId: String?
    @State private var statsRange: StatsRange = .today
    @State private var shiftStart: Date?
    @State private var shiftEnd: Date?
    @State private var isReviewDigestPresented = false
    @State private var isDataQualityPresented = false
    @State private var isShiftCalendarPresented = false
#if DEBUG
    @State private var showDebugPanel = false
#endif
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @ObservedObject var syncStore: WatchSyncStore

    init(syncStore: WatchSyncStore) {
        self.syncStore = syncStore
        _metaStore = StateObject(wrappedValue: SessionMetaStore())
        _timeOverrideStore = StateObject(wrappedValue: SessionTimeOverrideStore())
        _manualSessionStore = StateObject(wrappedValue: ManualSessionStore())
        let shiftStore = ShiftRecordStore()
        _shiftRecordStore = StateObject(wrappedValue: shiftStore)
        _dailyMemoStore = StateObject(wrappedValue: DailyMemoStore())
        _sessionVisibilityStore = StateObject(wrappedValue: SessionVisibilityStore())
        let defaults = UserDefaults.standard
        let start = defaults.object(forKey: "pf_shift_start") as? Date
        let end = defaults.object(forKey: "pf_shift_end") as? Date
        _shiftStart = State(initialValue: start)
        _shiftEnd = State(initialValue: end)
        shiftStore.seedFromLegacy(start: start, end: end)
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
                    Section("复盘备注") {
                        TextEditor(text: $draftReviewNote)
                            .frame(minHeight: 100)
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
        .sheet(item: $timeEditingSession) { session in
            timeOverrideEditor(sessionId: session.id)
        }
        .sheet(isPresented: $isManualSessionPresented) {
            manualSessionEditor
        }
        .onReceive(ticker) { now = $0 }
        .onReceive(syncStore.$incomingEvent) { event in
            guard let event = event else { return }
            applySessionEvent(event)
        }
    }

    private var effectiveSessionSummaries: [SessionSummary] {
        var byId: [String: SessionSummary] = [:]
        for summary in sessionSummaries {
            byId[summary.id] = summary
        }
        for manual in manualSessionStore.sessions.values {
            byId[manual.id] = SessionSummary(
                id: manual.id,
                shootingStart: manual.shootingStart,
                selectingStart: manual.selectingStart,
                endedAt: manual.endedAt
            )
        }
        return byId.values
            .filter { isSessionVisible($0.id) }
            .sorted { effectiveSessionSortKey(for: $0) < effectiveSessionSortKey(for: $1) }
    }

    private func effectiveTimes(for summary: SessionSummary) -> SessionTimes {
        if let overrideValue = timeOverrideStore.override(for: summary.id) {
            return SessionTimes(
                shootingStart: overrideValue.shootingStart,
                selectingStart: overrideValue.selectingStart,
                endedAt: overrideValue.endedAt
            )
        }
        return SessionTimes(
            shootingStart: summary.shootingStart,
            selectingStart: summary.selectingStart,
            endedAt: summary.endedAt
        )
    }

    private func effectiveSessionStartTime(for summary: SessionSummary) -> Date? {
        let times = effectiveTimes(for: summary)
        return [times.shootingStart, times.selectingStart, times.endedAt].compactMap { $0 }.min()
    }

    private func effectiveSessionSortKey(for summary: SessionSummary) -> Date {
        effectiveSessionStartTime(for: summary) ?? Date.distantPast
    }

    private var homeView: some View {
        return NavigationStack {
            VStack(spacing: 12) {
                homeFixedHeader

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text("会话时间线")
                            .font(.headline)
                        if effectiveSessionSummaries.isEmpty {
                            Text("暂无记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            let displaySessions = Array(effectiveSessionSummaries.reversed())
                            ForEach(Array(displaySessions.enumerated()), id: \.element.id) { displayIndex, summary in
                                let total = displaySessions.count
                                let order = total - displayIndex
                                let card = VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline) {
                                        HStack(spacing: 6) {
                                            Text("第\(order)单")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            if let startTime = effectiveSessionStartTime(for: summary) {
                                                Text(formatSessionTime(startTime))
                                                    .font(.footnote)
                                                    .foregroundStyle(.secondary)
                                                    .monospacedDigit()
                                            }
                                        }
                                        Spacer(minLength: 8)
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(amountText(for: summary))
                                                .font(.headline)
                                                .monospacedDigit()
                                            Text(rphText(for: summary))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        }
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
                                    if let notePreview = metaNotePreview(for: summary.id) {
                                        Text(notePreview)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink {
                                        sessionDetailView(summary: summary, order: order)
                                    } label: {
                                        card
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: { startEditingMeta(for: summary.id) }) {
                                        Image(systemName: "pencil")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                }
                            }
                        }
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private static let homeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()

    private var homeFixedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.homeDateFormatter.string(from: now))
                .font(.headline)
            todayBanner
            memoEditor
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memoEditor: some View {
        let dayKey = dailyMemoStore.dayKey(for: now)
        let placeholder = "备忘：客户/卡点/今天只做一件事…"
        return ZStack(alignment: .topLeading) {
            if memoDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(placeholder)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 6)
            }
            TextEditor(text: $memoDraft)
                .font(.footnote)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            memoDraft = dailyMemoStore.memo(for: dayKey)
        }
        .onChange(of: dayKey) { _, newKey in
            memoDraft = dailyMemoStore.memo(for: newKey)
        }
        .onChange(of: memoDraft) { _, newValue in
            dailyMemoStore.setMemo(newValue, for: dayKey)
        }
    }

    private func isSessionVisible(_ id: String) -> Bool {
        !sessionVisibilityStore.isDeleted(id) && !sessionVisibilityStore.isVoided(id)
    }

    private func toggleVoided(for id: String) {
        let isVoided = sessionVisibilityStore.isVoided(id)
        sessionVisibilityStore.setVoided(id, isVoided: !isVoided)
    }

    private func deleteSession(id: String) {
        if let index = sessionSummaries.firstIndex(where: { $0.id == id }),
           sessionSummaries[index].endedAt == nil {
            resetSession()
        }
        sessionVisibilityStore.markDeleted(id)
        metaStore.update(SessionMeta(), for: id)
        timeOverrideStore.clear(for: id)
        manualSessionStore.remove(id)
        sessionSummaries.removeAll { $0.id == id }
    }

    private func sessionDetailView(summary: SessionSummary, order: Int) -> some View {
        let meta = metaStore.meta(for: summary.id)
        let times = effectiveTimes(for: summary)
        let startTime = times.shootingStart ?? effectiveSessionStartTime(for: summary)
        let timeText = startTime.map(formatSessionTime) ?? "--"
        let amountText = meta.amountCents.map { formatAmount(cents: $0) } ?? "--"
        let rphLine = rphText(for: summary)
        let hasOverride = timeOverrideStore.override(for: summary.id) != nil
        let isVoided = sessionVisibilityStore.isVoided(summary.id)
        let deleteBinding = Binding<Bool>(
            get: { deleteCandidateId == summary.id },
            set: { isPresented in
                if !isPresented {
                    deleteCandidateId = nil
                }
            }
        )
        let shot = meta.shotCount
        let selected = meta.selectedCount
        let pickRateText: String = {
            guard let shot = shot, shot > 0, let selected = selected else { return "--" }
            if selected > shot { return "--" }
            if selected == shot { return "全要" }
            let rate = Int((Double(selected) / Double(shot) * 100).rounded())
            return "\(rate)%"
        }()
        let note = meta.reviewNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let noteText = note.isEmpty ? "暂无备注" : note

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("第\(order)单 \(timeText)")
                            .font(.headline)
                        Spacer(minLength: 8)
                        Text(amountText)
                            .font(.headline)
                            .monospacedDigit()
                    }
                    Text(rphLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if hasOverride {
                        Text("已更正")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("结算信息")
                        .font(.headline)
                    HStack {
                        Text("金额")
                        Spacer()
                        Text(amountText)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("拍摄张数")
                        Spacer()
                        Text(shot.map(String.init) ?? "--")
                    }
                    HStack {
                        Text("选片张数")
                        Spacer()
                        Text(selected.map(String.init) ?? "--")
                    }
                    HStack {
                        Text("选片率")
                        Spacer()
                        Text(pickRateText)
                    }
                }
                .font(.footnote)

                VStack(alignment: .leading, spacing: 8) {
                    Text("事件时间线")
                        .font(.headline)
                    HStack {
                        Text("拍摄开始")
                        Spacer()
                        Text(times.shootingStart.map(formatSessionTimeWithSeconds) ?? "--")
                            .monospacedDigit()
                    }
                    HStack {
                        Text("选片开始")
                        Spacer()
                        Text(times.selectingStart.map(formatSessionTimeWithSeconds) ?? "--")
                            .monospacedDigit()
                    }
                    HStack {
                        Text("结束")
                        Spacer()
                        Text(times.endedAt.map(formatSessionTimeWithSeconds) ?? "--")
                            .monospacedDigit()
                    }
                }
                .font(.footnote)

                VStack(alignment: .leading, spacing: 8) {
                    Text("复盘备注")
                        .font(.headline)
                    Text(noteText)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("复制备注") {
                        UIPasteboard.general.string = note
                    }
                    .buttonStyle(.bordered)
                    .disabled(note.isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("本单操作")
                        .font(.headline)
                    HStack(spacing: 12) {
                        Button(isVoided ? "恢复" : "作废") {
                            toggleVoided(for: summary.id)
                        }
                        .buttonStyle(.bordered)
                        Button("删除") {
                            deleteCandidateId = summary.id
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("单子详情")
        .confirmationDialog("删除本单？", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                deleteSession(id: summary.id)
                deleteCandidateId = nil
            }
            Button("取消", role: .cancel) {
                deleteCandidateId = nil
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button("更正时间") {
                    startEditingTime(for: summary)
                }
                Button("编辑") {
                    startEditingMeta(for: summary.id)
                }
            }
        }
    }

    private func startManualSessionDraft() {
        let start = now
        draftManualShootingStart = start
        draftManualEndedAt = start.addingTimeInterval(60)
        draftManualSelectingEnabled = false
        draftManualSelectingStart = start
        draftManualAmount = ""
        draftManualShotCount = ""
        draftManualSelectedCount = ""
        draftManualReviewNote = ""
        isManualSessionPresented = true
    }

    private func saveManualSession() {
        let start = draftManualShootingStart
        let end = draftManualEndedAt
        guard start < end else {
            activeAlert = .validation("拍摄开始需早于结束时间")
            return
        }
        if draftManualSelectingEnabled {
            let selecting = draftManualSelectingStart
            guard selecting >= start && selecting <= end else {
                activeAlert = .validation("选片开始需在拍摄开始与结束之间")
                return
            }
        }
        let sessionId = makeManualSessionId(startedAt: start)
        let manual = ManualSession(
            id: sessionId,
            shootingStart: start,
            selectingStart: draftManualSelectingEnabled ? draftManualSelectingStart : nil,
            endedAt: end
        )
        manualSessionStore.upsert(manual)
        let meta = SessionMeta(
            amountCents: parseAmountCents(from: draftManualAmount),
            shotCount: parseInt(from: draftManualShotCount),
            selectedCount: parseInt(from: draftManualSelectedCount),
            reviewNote: normalizedNote(from: draftManualReviewNote)
        )
        metaStore.update(meta, for: sessionId)
        isManualSessionPresented = false
    }

    private var manualSessionEditor: some View {
        NavigationStack {
            Form {
                Section("时间") {
                    DatePicker("拍摄开始", selection: $draftManualShootingStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束", selection: $draftManualEndedAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle("有选片开始", isOn: $draftManualSelectingEnabled)
                    if draftManualSelectingEnabled {
                        DatePicker("选片开始", selection: $draftManualSelectingStart, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section("结算") {
                    TextField("金额", text: $draftManualAmount)
                        .keyboardType(.decimalPad)
                    TextField("拍摄张数", text: $draftManualShotCount)
                        .keyboardType(.numberPad)
                    TextField("选片张数", text: $draftManualSelectedCount)
                        .keyboardType(.numberPad)
                }
                Section("复盘备注") {
                    TextEditor(text: $draftManualReviewNote)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("补记一单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isManualSessionPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveManualSession()
                    }
                }
            }
        }
    }

    private func startEditingTime(for summary: SessionSummary) {
        let times = effectiveTimes(for: summary)
        draftOverrideShootingStart = times.shootingStart ?? now
        draftOverrideSelectingEnabled = times.selectingStart != nil
        draftOverrideSelectingStart = times.selectingStart ?? draftOverrideShootingStart
        draftOverrideEndedEnabled = times.endedAt != nil
        draftOverrideEndedAt = times.endedAt ?? now
        timeEditingSession = TimeEditingSession(id: summary.id)
    }

    private func saveTimeOverride(for sessionId: String) {
        let start = draftOverrideShootingStart
        let end = draftOverrideEndedEnabled ? draftOverrideEndedAt : nil
        if let end, start >= end {
            activeAlert = .validation("拍摄开始需早于结束时间")
            return
        }
        if draftOverrideSelectingEnabled {
            let selecting = draftOverrideSelectingStart
            let validationEnd = end ?? now
            guard selecting >= start && selecting <= validationEnd else {
                activeAlert = .validation("选片开始需在拍摄开始与结束之间")
                return
            }
        }
        let overrideValue = SessionTimeOverride(
            shootingStart: start,
            selectingStart: draftOverrideSelectingEnabled ? draftOverrideSelectingStart : nil,
            endedAt: end,
            updatedAt: now
        )
        timeOverrideStore.update(overrideValue, for: sessionId)
        timeEditingSession = nil
    }

    private func timeOverrideEditor(sessionId: String) -> some View {
        NavigationStack {
            Form {
                Section("时间更正") {
                    DatePicker("拍摄开始", selection: $draftOverrideShootingStart, displayedComponents: [.date, .hourAndMinute])
                    Toggle("有选片开始", isOn: $draftOverrideSelectingEnabled)
                    if draftOverrideSelectingEnabled {
                        DatePicker("选片开始", selection: $draftOverrideSelectingStart, displayedComponents: [.date, .hourAndMinute])
                    }
                    Toggle("有结束时间", isOn: $draftOverrideEndedEnabled)
                    if draftOverrideEndedEnabled {
                        DatePicker("结束", selection: $draftOverrideEndedAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section {
                    Button("清除更正", role: .destructive) {
                        timeOverrideStore.clear(for: sessionId)
                        timeEditingSession = nil
                    }
                }
            }
            .navigationTitle("更正时间")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        timeEditingSession = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveTimeOverride(for: sessionId)
                    }
                }
            }
        }
    }

    private func dataQualityListView(
        missing: [DataQualityItem],
        anomaly: [DataQualityItem],
        orderById: [String: Int]
    ) -> some View {
        NavigationStack {
            List {
                Section("缺失") {
                    if missing.isEmpty {
                        Text("暂无缺失")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(missing) { item in
                            let order = orderById[item.summary.id] ?? 1
                            NavigationLink {
                                sessionDetailView(summary: item.summary, order: order)
                            } label: {
                                Text(item.text)
                            }
                        }
                    }
                }
                Section("异常") {
                    if anomaly.isEmpty {
                        Text("暂无异常")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(anomaly) { item in
                            let order = orderById[item.summary.id] ?? 1
                            NavigationLink {
                                sessionDetailView(summary: item.summary, order: order)
                            } label: {
                                Text(item.text)
                            }
                        }
                    }
                }
            }
            .navigationTitle("数据质量")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") {
                        isDataQualityPresented = false
                    }
                }
            }
        }
    }

    private var shiftCalendarView: some View {
        ShiftCalendarView(
            sessions: effectiveSessionSummaries,
            metaStore: metaStore,
            shiftRecordStore: shiftRecordStore,
            now: now,
            effectiveShootingStart: { summary in
                effectiveTimes(for: summary).shootingStart
            },
            formatAmount: { cents in
                formatAmount(cents: cents)
            },
            formatTime: { date in
                formatSessionTime(date)
            },
            onUpdateRecord: { day, record in
                updateShiftRecord(record, for: day)
            }
        )
    }

    private func updateShiftRecord(_ record: ShiftRecord, for day: Date) {
        let key = shiftRecordStore.dayKey(for: day)
        shiftRecordStore.upsert(record, for: key)
        syncShiftStateIfNeeded(for: day, record: record)
    }

    private func syncShiftStateIfNeeded(for day: Date, record: ShiftRecord) {
        let isoCal = Calendar(identifier: .iso8601)
        guard isoCal.isDateInToday(day) else { return }
        shiftStart = record.startAt
        shiftEnd = record.endAt
        let defaults = UserDefaults.standard
        defaults.set(shiftStart, forKey: "pf_shift_start")
        defaults.set(shiftEnd, forKey: "pf_shift_end")
    }

    private var todayBanner: some View {
        let isoCal = Calendar(identifier: .iso8601)
        let todaySessions = effectiveSessionSummaries.filter { summary in
            guard let shootingStart = effectiveTimes(for: summary).shootingStart else { return false }
            return isoCal.isDateInToday(shootingStart)
        }
        let totals = todaySessions.reduce(into: (total: TimeInterval(0), shooting: TimeInterval(0), selecting: TimeInterval(0))) { result, summary in
            let durations = sessionDurations(for: summary)
            result.total += durations.total
            result.shooting += durations.shooting
            if let selecting = durations.selecting {
                result.selecting += selecting
            }
        }
        let metaTotals = todaySessions.reduce(into: (amountCents: 0, hasAmount: false, shot: 0, hasShot: false, selected: 0, hasSelected: false)) { result, summary in
            let meta = metaStore.meta(for: summary.id)
            if let amount = meta.amountCents {
                result.amountCents += amount
                result.hasAmount = true
            }
            if let shot = meta.shotCount {
                result.shot += shot
                result.hasShot = true
            }
            if let selected = meta.selectedCount {
                result.selected += selected
                result.hasSelected = true
            }
        }
        let count = todaySessions.count
        let amountText = metaTotals.hasAmount ? formatAmount(cents: metaTotals.amountCents) : "--"
        let rateText = (metaTotals.hasShot && metaTotals.hasSelected && metaTotals.shot > 0)
            ? "\(Int((Double(metaTotals.selected) / Double(metaTotals.shot) * 100).rounded()))%"
            : "--"
        return Button(action: { selectedTab = .stats }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今日收入")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(amountText)
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                Text("\(count)单 · 总 \(format(totals.total))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("拍 \(format(totals.shooting)) · 选 \(format(totals.selecting)) · 拍 \(metaTotals.hasShot ? "\(metaTotals.shot)张" : "--") · 选 \(metaTotals.hasSelected ? "\(metaTotals.selected)张" : "--") · 选片率 \(rateText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var statsView: some View {
        let isoCal = Calendar(identifier: .iso8601)
        let filteredSessions = effectiveSessionSummaries.filter { summary in
            guard let shootingStart = effectiveTimes(for: summary).shootingStart else { return false }
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
        let bizTotals = filteredSessions.reduce(into: (amountCents: 0, hasAmount: false, shot: 0, hasShot: false, selected: 0, hasSelected: false)) { result, summary in
            let meta = metaStore.meta(for: summary.id)
            if let amount = meta.amountCents {
                result.amountCents += amount
                result.hasAmount = true
            }
            if let shot = meta.shotCount {
                result.shot += shot
                result.hasShot = true
            }
            if let selected = meta.selectedCount {
                result.selected += selected
                result.hasSelected = true
            }
        }
        let revenueText = bizTotals.hasAmount ? formatAmount(cents: bizTotals.amountCents) : "--"
        let avgRevenueText = (bizTotals.hasAmount && count > 0)
            ? formatAmount(cents: Int((Double(bizTotals.amountCents) / Double(count)).rounded()))
            : "--"
        let shotText = bizTotals.hasShot ? "\(bizTotals.shot)" : "--"
        let selectedText = bizTotals.hasSelected ? "\(bizTotals.selected)" : "--"
        let selectRateText = (bizTotals.hasShot && bizTotals.hasSelected && bizTotals.shot > 0)
            ? "\(Int((Double(bizTotals.selected) / Double(bizTotals.shot) * 100).rounded()))%"
            : "--"
        let rphText: String = {
            guard bizTotals.hasAmount, totals.total > 0 else { return "--" }
            let hours = totals.total / 3600
            let revenue = Double(bizTotals.amountCents) / 100
            return String(format: "¥%.0f/小时", revenue / hours)
        }()
        let (avgSelectRateText, allTakeShareText, weightedPickRateText): (String, String, String) = {
            var sumRatio: Double = 0
            var avgCount = 0
            var allTakeCount = 0
            var sumSelected = 0
            var sumShot = 0
            for summary in filteredSessions {
                let meta = metaStore.meta(for: summary.id)
                guard let shot = meta.shotCount, shot > 0,
                      let selected = meta.selectedCount else { continue }
                if selected > shot {
                    continue
                }
                if selected == shot {
                    allTakeCount += 1
                    continue
                }
                sumRatio += Double(selected) / Double(shot)
                avgCount += 1
                sumSelected += selected
                sumShot += shot
            }
            let avgText: String
            if avgCount > 0 {
                let avg = sumRatio / Double(avgCount)
                avgText = "\(Int((avg * 100).rounded()))%"
            } else {
                avgText = "--"
            }
            let denom = allTakeCount + avgCount
            let shareText = denom > 0
                ? "\(Int((Double(allTakeCount) / Double(denom) * 100).rounded()))%"
                : "--"
            let weightedText = sumShot > 0
                ? "\(Int((Double(sumSelected) / Double(sumShot) * 100).rounded()))%"
                : "--"
            return (avgText, shareText, weightedText)
        }()
        let reviewDigestText = dailyReviewDigestText()
        let orderById = Dictionary(uniqueKeysWithValues: effectiveSessionSummaries.enumerated().map { ($0.element.id, $0.offset + 1) })
        let sessionLabel: (SessionSummary) -> String = { summary in
            var parts: [String] = []
            if let order = orderById[summary.id] {
                parts.append("第\(order)单")
            } else {
                parts.append("第?单")
            }
            if let start = effectiveSessionStartTime(for: summary) {
                parts.append(formatSessionTime(start))
            }
            return parts.joined(separator: " ")
        }
        let revenueTop3: [(SessionSummary, Int)] = {
            let items = filteredSessions.compactMap { summary -> (SessionSummary, Int)? in
                let meta = metaStore.meta(for: summary.id)
                guard let amount = meta.amountCents else { return nil }
                return (summary, amount)
            }
            return Array(items.sorted { $0.1 > $1.1 }.prefix(3))
        }()
        let rphTop3: [(SessionSummary, Double)] = {
            let items = filteredSessions.compactMap { summary -> (SessionSummary, Double)? in
                let meta = metaStore.meta(for: summary.id)
                guard let amount = meta.amountCents else { return nil }
                let totalSeconds = sessionDurations(for: summary).total
                guard totalSeconds > 0 else { return nil }
                let hours = totalSeconds / 3600
                let revenue = Double(amount) / 100
                return (summary, revenue / hours)
            }
            return Array(items.sorted { $0.1 > $1.1 }.prefix(3))
        }()
        let durationTop3: [(SessionSummary, TimeInterval)] = {
            let items = filteredSessions.compactMap { summary -> (SessionSummary, TimeInterval)? in
                let totalSeconds = sessionDurations(for: summary).total
                guard totalSeconds > 0 else { return nil }
                return (summary, totalSeconds)
            }
            return Array(items.sorted { $0.1 > $1.1 }.prefix(3))
        }()
        let dataQuality = dataQualityReport(for: filteredSessions, sessionLabel: sessionLabel)
        let shiftWindow: (start: Date, end: Date)? = {
            guard let start = shiftStart else { return nil }
            let end = shiftEnd ?? (syncStore.isOnDuty ? now : nil)
            guard let end, end > start else { return nil }
            return (start, end)
        }()
        let mergedWorkIntervals: [(Date, Date)] = {
            guard let shiftWindow else { return [] }
            let raw = filteredSessions.compactMap { summary -> (Date, Date)? in
                let times = effectiveTimes(for: summary)
                guard let start = times.shootingStart else { return nil }
                let end = times.endedAt ?? now
                return (start, end)
            }
            let clipped = raw.compactMap { interval -> (Date, Date)? in
                let start = max(interval.0, shiftWindow.start)
                let end = min(interval.1, shiftWindow.end)
                return end > start ? (start, end) : nil
            }
            let sorted = clipped.sorted { $0.0 < $1.0 }
            var merged: [(Date, Date)] = []
            for interval in sorted {
                if let last = merged.last, interval.0 <= last.1 {
                    let newEnd = max(last.1, interval.1)
                    merged[merged.count - 1].1 = newEnd
                } else {
                    merged.append(interval)
                }
            }
            return merged
        }()
        let shiftTotals: (work: TimeInterval, idle: TimeInterval, utilization: String, segments: [(TimeInterval, Bool)]) = {
            guard let shiftWindow else { return (0, 0, "--", []) }
            let shiftDuration = shiftWindow.end.timeIntervalSince(shiftWindow.start)
            guard shiftDuration > 0 else { return (0, 0, "--", []) }
            let workTotal = mergedWorkIntervals.reduce(0) { $0 + $1.1.timeIntervalSince($1.0) }
            let idleTotal = max(0, shiftDuration - workTotal)
            let utilization = "\(Int((workTotal / shiftDuration * 100).rounded()))%"
            var idleIntervals: [(Date, Date)] = []
            var cursor = shiftWindow.start
            for work in mergedWorkIntervals {
                if work.0 > cursor {
                    idleIntervals.append((cursor, work.0))
                }
                cursor = max(cursor, work.1)
            }
            if cursor < shiftWindow.end {
                idleIntervals.append((cursor, shiftWindow.end))
            }
            var segments: [(Date, Date, Bool)] = []
            segments.append(contentsOf: mergedWorkIntervals.map { ($0.0, $0.1, true) })
            segments.append(contentsOf: idleIntervals.map { ($0.0, $0.1, false) })
            segments.sort { $0.0 < $1.0 }
            let barSegments = segments.map { ($0.1.timeIntervalSince($0.0), $0.2) }
            return (workTotal, idleTotal, utilization, barSegments)
        }()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $statsRange) {
                ForEach(StatsRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Button("记录（月历）") {
                isShiftCalendarPresented = true
            }
            .buttonStyle(.bordered)

            Text("上班时间线")
                .font(.headline)
            if statsRange != .today {
                Text("仅今日显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let shiftWindow {
                let shiftStartText = formatSessionTime(shiftWindow.start)
                let shiftEndText = shiftEnd == nil ? "进行中" : formatSessionTime(shiftWindow.end)
                Text("上班 \(shiftStartText) · 下班 \(shiftEndText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("工作 \(format(shiftTotals.work)) · 空余 \(format(shiftTotals.idle)) · 利用率 \(shiftTotals.utilization)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        ForEach(Array(shiftTotals.segments.enumerated()), id: \.offset) { _, segment in
                            let width = proxy.size.width * segment.0 / max(1, shiftWindow.end.timeIntervalSince(shiftWindow.start))
                            Rectangle()
                                .fill(segment.1 ? Color.primary : Color.secondary.opacity(0.25))
                                .frame(width: width)
                        }
                    }
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 12)
            } else {
                Text("暂无上班记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if statsRange == .today {
                Button("补记一单") {
                    startManualSessionDraft()
                }
                .buttonStyle(.bordered)
            } else {
                Text("仅今日可补记")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("今日复盘备注")
                .font(.headline)
            Button("查看/复制") {
                isReviewDigestPresented = true
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $isReviewDigestPresented) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 12) {
                        ScrollView {
                            Text(reviewDigestText)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 12) {
                            Button("复制") {
                                UIPasteboard.general.string = reviewDigestText
                            }
                            ShareLink(item: reviewDigestText) {
                                Text("分享")
                            }
                        }
                    }
                    .padding()
                    .navigationTitle("今日复盘备注")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") {
                                isReviewDigestPresented = false
                            }
                        }
                    }
                }
            }
            Divider()

            Text("\(prefix)单数 \(count)")
            Text("\(prefix)总时长 \(format(totals.total))")
            Text("\(prefix)拍摄时长 \(format(totals.shooting))")
            Text("\(prefix)选片时长 \(format(totals.selecting))")
            Text("\(prefix)平均每单总时长 \(avgText)")
            Text("\(prefix)选片占比 \(shareText)")
            Divider()
            Text("经营汇总")
                .font(.headline)
            Text("收入合计 \(revenueText)")
            Text("平均客单价 \(avgRevenueText)")
            Text("拍摄张数合计 \(shotText)")
            Text("选片张数合计 \(selectedText)")
            Text("选片率 \(selectRateText)")
            Text("RPH \(rphText)")
            Text("平均选片率（按单） \(avgSelectRateText)（全要 \(allTakeShareText)）")
            Text("选片率（按张） \(weightedPickRateText)")
            Divider()
            Text("Top 3")
                .font(.headline)
            Text("收入")
                .font(.subheadline)
            if revenueTop3.isEmpty {
                Text("暂无足够数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(revenueTop3.enumerated()), id: \.offset) { _, item in
                    Text("\(sessionLabel(item.0))  \(formatAmount(cents: item.1))")
                }
            }
            Text("RPH")
                .font(.subheadline)
            if rphTop3.isEmpty {
                Text("暂无足够数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rphTop3.enumerated()), id: \.offset) { _, item in
                    let rphLine = String(format: "RPH ¥%.0f/小时", item.1)
                    Text("\(sessionLabel(item.0))  \(rphLine)")
                }
            }
            Text("用时")
                .font(.subheadline)
            if durationTop3.isEmpty {
                Text("暂无足够数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(durationTop3.enumerated()), id: \.offset) { _, item in
                    Text("\(sessionLabel(item.0))  用时 \(format(item.1))")
                }
            }
            Divider()
            Text("数据质量")
                .font(.headline)
            Text("缺失 \(dataQuality.missing.count) · 异常 \(dataQuality.anomaly.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("查看") {
                isDataQualityPresented = true
            }
            .buttonStyle(.bordered)
            .disabled(dataQuality.missing.isEmpty && dataQuality.anomaly.isEmpty)
            .sheet(isPresented: $isDataQualityPresented) {
                dataQualityListView(
                    missing: dataQuality.missing,
                    anomaly: dataQuality.anomaly,
                    orderById: orderById
                )
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .sheet(isPresented: $isShiftCalendarPresented) {
            shiftCalendarView
        }
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
        if syncStore.isOnDuty {
            let durations = computeDurations(now: now)
            return AnyView(
                Button(action: performNextAction) {
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
                    Button("下班", role: .destructive) { setDuty(false) }
                }
            )
        }
        return AnyView(
            Button(action: { setDuty(true) }) {
                Text("上班")
                    .font(.headline)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        )
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

    private func setDuty(_ onDuty: Bool) {
        syncStore.setOnDuty(onDuty)
        let key = shiftRecordStore.dayKey(for: now)
        var record = shiftRecordStore.record(for: key) ?? ShiftRecord()
        if onDuty {
            if record.startAt == nil {
                record.startAt = now
            }
            record.endAt = nil
            shiftStart = record.startAt
            shiftEnd = nil
        } else {
            if record.startAt == nil {
                record.startAt = shiftStart ?? now
            }
            record.endAt = now
            shiftEnd = now
            resetSession()
        }
        shiftRecordStore.upsert(record, for: key)
        let defaults = UserDefaults.standard
        defaults.set(shiftStart, forKey: "pf_shift_start")
        defaults.set(shiftEnd, forKey: "pf_shift_end")
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

    private static let sessionTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let sessionTimeWithSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let reviewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func formatSessionTime(_ date: Date) -> String {
        ContentView.sessionTimeFormatter.string(from: date)
    }

    private func formatSessionTimeWithSeconds(_ date: Date) -> String {
        ContentView.sessionTimeWithSecondsFormatter.string(from: date)
    }

    private func reviewDateText(_ date: Date) -> String {
        ContentView.reviewDateFormatter.string(from: date)
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

    private func dataQualityReport(
        for sessions: [SessionSummary],
        sessionLabel: (SessionSummary) -> String
    ) -> (missing: [DataQualityItem], anomaly: [DataQualityItem]) {
        var missingItems: [DataQualityItem] = []
        var anomalyItems: [DataQualityItem] = []
        let ordered = sessions.sorted { effectiveSessionSortKey(for: $0) < effectiveSessionSortKey(for: $1) }
        for summary in ordered {
            let meta = metaStore.meta(for: summary.id)
            let label = sessionLabel(summary)
            var missingParts: [String] = []
            if meta.amountCents == nil {
                missingParts.append("缺金额")
            }
            if (meta.shotCount ?? 0) <= 0 {
                missingParts.append("缺拍")
            }
            if meta.selectedCount == nil {
                missingParts.append("缺选")
            }
            let note = meta.reviewNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if note.isEmpty {
                missingParts.append("缺备注")
            }
            if !missingParts.isEmpty {
                let text = "\(label)：\(missingParts.joined(separator: " / "))"
                missingItems.append(DataQualityItem(summary: summary, text: text))
            }

            var anomalyParts: [String] = []
            if let shot = meta.shotCount, let selected = meta.selectedCount {
                if shot == 0 && selected > 0 {
                    anomalyParts.append("拍摄=0但有选片")
                } else if selected > shot {
                    anomalyParts.append("选片>拍摄")
                }
            }
            let total = sessionDurations(for: summary).total
            if total <= 0 {
                anomalyParts.append("总时长=0")
            }
            if !anomalyParts.isEmpty {
                let text = "\(label)：\(anomalyParts.joined(separator: " / "))"
                anomalyItems.append(DataQualityItem(summary: summary, text: text))
            }
        }
        return (missingItems, anomalyItems)
    }

    private func startEditingMeta(for sessionId: String) {
        let meta = metaStore.meta(for: sessionId)
        draftAmount = meta.amountCents.map(amountText(from:)) ?? ""
        draftShotCount = meta.shotCount.map(String.init) ?? ""
        draftSelected = meta.selectedCount.map(String.init) ?? ""
        draftReviewNote = meta.reviewNote ?? ""
        editingSession = EditingSession(id: sessionId)
    }

    private func saveMeta(for sessionId: String) {
        let meta = SessionMeta(
            amountCents: parseAmountCents(from: draftAmount),
            shotCount: parseInt(from: draftShotCount),
            selectedCount: parseInt(from: draftSelected),
            reviewNote: normalizedNote(from: draftReviewNote)
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
        let shot = meta.shotCount
        let selected = meta.selectedCount
        if let shot {
            parts.append("拍\(shot)张")
        }
        if let shot, let selected {
            if selected > shot {
                return parts.isEmpty ? nil : parts.joined(separator: " · ")
            }
            if shot > 0 && selected == shot {
                parts.append("全要")
                return parts.joined(separator: " · ")
            }
            parts.append("选\(selected)张")
            if shot > 0 && selected < shot {
                let rate = Int((Double(selected) / Double(shot) * 100).rounded())
                parts.append("选片率\(rate)%")
            }
            return parts.joined(separator: " · ")
        }
        if shot == nil, let selected {
            parts.append("选\(selected)张")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func dailyReviewDigestText() -> String {
        let isoCal = Calendar(identifier: .iso8601)
        let todaySessions = effectiveSessionSummaries.filter { summary in
            guard let shootingStart = effectiveTimes(for: summary).shootingStart else { return false }
            return isoCal.isDateInToday(shootingStart)
        }
        let ordered = todaySessions.sorted { effectiveSessionSortKey(for: $0) < effectiveSessionSortKey(for: $1) }
        var lines: [String] = []
        for (index, summary) in ordered.enumerated() {
            let meta = metaStore.meta(for: summary.id)
            let note = meta.reviewNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !note.isEmpty else { continue }
            var parts: [String] = []
            let order = index + 1
            let timeText = formatSessionTime(effectiveSessionStartTime(for: summary) ?? effectiveSessionSortKey(for: summary))
            parts.append("第\(order)单 \(timeText)")
            if let amount = meta.amountCents {
                parts.append(formatAmount(cents: amount))
            }
            if let shot = meta.shotCount {
                parts.append("拍\(shot)")
            }
            if let selected = meta.selectedCount {
                parts.append("选\(selected)")
            }
            let line = parts.joined(separator: "  ") + "  ——  " + note
            lines.append(line)
        }
        let header = "\(reviewDateText(now)) 今日复盘备注"
        if lines.isEmpty {
            return "\(header)\n暂无备注"
        }
        return ([header] + lines).joined(separator: "\n")
    }

    private func amountText(for summary: SessionSummary) -> String {
        let meta = metaStore.meta(for: summary.id)
        return meta.amountCents.map { formatAmount(cents: $0) } ?? "--"
    }

    private func rphText(for summary: SessionSummary) -> String {
        let meta = metaStore.meta(for: summary.id)
        guard let amountCents = meta.amountCents else { return "RPH --" }
        let totalSeconds = sessionDurations(for: summary).total
        guard totalSeconds > 0 else { return "RPH --" }
        let revenue = Double(amountCents) / 100
        let hours = totalSeconds / 3600
        return String(format: "RPH ¥%.0f/小时", revenue / hours)
    }

    private func metaNotePreview(for sessionId: String) -> String? {
        guard let note = metaStore.meta(for: sessionId).reviewNote else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func normalizedNote(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sessionDurations(for summary: SessionSummary) -> (total: TimeInterval, shooting: TimeInterval, selecting: TimeInterval?) {
        let times = effectiveTimes(for: summary)
        guard let shootingStart = times.shootingStart else {
            return (0, 0, nil)
        }
        let endTime = times.endedAt ?? now
        let total = max(0, endTime.timeIntervalSince(shootingStart))

        let shooting: TimeInterval
        if let selectingStart = times.selectingStart {
            shooting = max(0, selectingStart.timeIntervalSince(shootingStart))
        } else if let endedAt = times.endedAt {
            shooting = max(0, endedAt.timeIntervalSince(shootingStart))
        } else {
            shooting = max(0, now.timeIntervalSince(shootingStart))
        }

        let selecting: TimeInterval?
        if let selectingStart = times.selectingStart {
            let selectingEnd = times.endedAt ?? now
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

    private func makeManualSessionId(startedAt: Date) -> String {
        let base = "manual-\(Int(startedAt.timeIntervalSince1970 * 1000))"
        if sessionSummaries.contains(where: { $0.id == base }) || manualSessionStore.session(for: base) != nil {
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

private struct ShiftCalendarView: View {
    let sessions: [ContentView.SessionSummary]
    @ObservedObject var metaStore: SessionMetaStore
    @ObservedObject var shiftRecordStore: ShiftRecordStore
    let now: Date
    let effectiveShootingStart: (ContentView.SessionSummary) -> Date?
    let formatAmount: (Int) -> String
    let formatTime: (Date) -> String
    let onUpdateRecord: (Date, ShiftRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var monthCursor: Date
    @State private var selectedDay: Date?
    @State private var editingDay: EditingDay?
    @State private var draftStart = Date()
    @State private var draftEnd = Date()
    @State private var draftHasEnd = true

    private let calendar = Calendar(identifier: .iso8601)

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    init(
        sessions: [ContentView.SessionSummary],
        metaStore: SessionMetaStore,
        shiftRecordStore: ShiftRecordStore,
        now: Date,
        effectiveShootingStart: @escaping (ContentView.SessionSummary) -> Date?,
        formatAmount: @escaping (Int) -> String,
        formatTime: @escaping (Date) -> String,
        onUpdateRecord: @escaping (Date, ShiftRecord) -> Void
    ) {
        self.sessions = sessions
        self.metaStore = metaStore
        self.shiftRecordStore = shiftRecordStore
        self.now = now
        self.effectiveShootingStart = effectiveShootingStart
        self.formatAmount = formatAmount
        self.formatTime = formatTime
        self.onUpdateRecord = onUpdateRecord
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        _monthCursor = State(initialValue: monthStart)
        _selectedDay = State(initialValue: calendar.startOfDay(for: now))
    }

    var body: some View {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: monthCursor)) ?? monthCursor
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: monthStart)) ?? monthStart
        let days = monthDays(start: monthStart)
        let yearDays = yearDays(start: yearStart)
        let leading = leadingBlankCount(monthStart: monthStart)
        let incomeByDay = dailyIncome()
        let monthIncome = days.reduce(0) { $0 + (incomeByDay[shiftRecordStore.dayKey(for: $1)] ?? 0) }
        let hasMonthIncome = days.contains { incomeByDay[shiftRecordStore.dayKey(for: $0)] != nil }
        let monthShift = days.reduce(0) { $0 + shiftInfo(for: $1).duration }
        let yearIncome = yearDays.reduce(0) { $0 + (incomeByDay[shiftRecordStore.dayKey(for: $1)] ?? 0) }
        let hasYearIncome = yearDays.contains { incomeByDay[shiftRecordStore.dayKey(for: $0)] != nil }
        let yearShift = yearDays.reduce(0) { $0 + shiftInfo(for: $1).duration }

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button {
                            monthCursor = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        Text(Self.monthFormatter.string(from: monthStart))
                            .font(.headline)
                        Spacer()
                        Button {
                            monthCursor = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                    }

                    let yearIncomeText = hasYearIncome ? formatAmount(yearIncome) : "--"
                    Text("本年总收入 \(yearIncomeText) · 本年上班时长 \(formatHours(yearShift))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    let weekdaySymbols = weekdayHeaders()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                        }

                        ForEach(0..<leading, id: \.self) { _ in
                            Color.clear.frame(height: 62)
                        }

                        ForEach(days, id: \.self) { day in
                            let key = shiftRecordStore.dayKey(for: day)
                            let income = incomeByDay[key] ?? 0
                            let shift = shiftInfo(for: day)
                            let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
                            let incomeText = income > 0 ? formatAmount(income) : nil
                            let shiftText = shift.duration > 0 ? formatHours(shift.duration) : nil
                            let placeholderIncome = formatAmount(0)
                            let placeholderShift = formatHours(0)
                            Button {
                                selectedDay = calendar.startOfDay(for: day)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(calendar.component(.day, from: day))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if shift.isOngoing {
                                            Circle()
                                                .fill(Color.orange)
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                    Group {
                                        if let incomeText {
                                            Text(incomeText)
                                        } else {
                                            Text(placeholderIncome).hidden()
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Group {
                                        if let shiftText {
                                            Text(shiftText)
                                        } else {
                                            Text(placeholderShift).hidden()
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                                .background(isSelected ? Color.primary.opacity(0.08) : Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    let monthIncomeText = hasMonthIncome ? formatAmount(monthIncome) : "--"
                    Text("本月收入 \(monthIncomeText) · 本月上班时长 \(formatHours(monthShift))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let selectedDay {
                        let key = shiftRecordStore.dayKey(for: selectedDay)
                        let record = shiftRecordStore.record(for: key)
                        let shift = shiftInfo(for: selectedDay)
                        let startText = record?.startAt.map(formatTime) ?? "--"
                        let endText = record?.endAt.map(formatTime) ?? (record?.startAt != nil ? "进行中" : "--")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("明细")
                                .font(.headline)
                            HStack {
                                Text("上班 \(startText)")
                                Text("下班 \(endText)")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            Text("上班时长 \(shift.display)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button(record == nil ? "补记" : "编辑") {
                                    startEditing(day: selectedDay, record: record)
                                }
                                .buttonStyle(.bordered)
                                if record?.startAt != nil, record?.endAt == nil {
                                    Button("补下班") {
                                        let end = min(now, dayEnd(for: selectedDay))
                                        onUpdateRecord(selectedDay, ShiftRecord(startAt: record?.startAt, endAt: end))
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("记录（月历）")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startEditing(day: selectedDay ?? now, record: shiftRecordStore.record(for: shiftRecordStore.dayKey(for: selectedDay ?? now)))
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingDay) { day in
                let selected = day.date
                NavigationStack {
                    Form {
                        Section("上班时间") {
                            DatePicker("上班", selection: $draftStart, displayedComponents: [.hourAndMinute])
                            Toggle("有下班时间", isOn: $draftHasEnd)
                            if draftHasEnd {
                                DatePicker("下班", selection: $draftEnd, displayedComponents: [.hourAndMinute])
                            }
                        }
                    }
                    .navigationTitle("编辑班次")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
                                editingDay = nil
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                let start = draftStart
                                var end = draftHasEnd ? draftEnd : nil
                                if let endValue = end, endValue < start {
                                    end = start
                                }
                                onUpdateRecord(selected, ShiftRecord(startAt: start, endAt: end))
                                editingDay = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private func monthDays(start: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }

    private func yearDays(start: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .year, for: start) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }

    private func leadingBlankCount(monthStart: Date) -> Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        let offset = weekday - calendar.firstWeekday
        return (offset + 7) % 7
    }

    private func weekdayHeaders() -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let startIndex = calendar.firstWeekday - 1
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private func dailyIncome() -> [String: Int] {
        var totals: [String: Int] = [:]
        for summary in sessions {
            guard let start = effectiveShootingStart(summary) else { continue }
            let key = shiftRecordStore.dayKey(for: start)
            if let amount = metaStore.meta(for: summary.id).amountCents {
                totals[key, default: 0] += amount
            }
        }
        return totals
    }

    private func dayEnd(for day: Date) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    private func shiftInfo(for day: Date) -> (duration: TimeInterval, isOngoing: Bool, display: String) {
        let key = shiftRecordStore.dayKey(for: day)
        guard let record = shiftRecordStore.record(for: key),
              let startAt = record.startAt else {
            return (0, false, "--")
        }
        let startOfDay = calendar.startOfDay(for: day)
        let endOfDay = dayEnd(for: day)
        let effectiveStart = max(startAt, startOfDay)
        let effectiveEnd = min(record.endAt ?? now, endOfDay)
        let duration = max(0, effectiveEnd.timeIntervalSince(effectiveStart))
        let isOngoing = record.endAt == nil
        return (duration, isOngoing, formatHours(duration))
    }

    private func formatHours(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "0.0h" }
        let hours = duration / 3600
        return String(format: "%.1fh", hours)
    }

    private func startEditing(day: Date, record: ShiftRecord?) {
        let dayStart = calendar.startOfDay(for: day)
        let defaultStart = calendar.date(byAdding: .hour, value: 9, to: dayStart) ?? dayStart
        let defaultEnd = calendar.date(byAdding: .hour, value: 18, to: dayStart) ?? dayStart
        draftStart = record?.startAt ?? defaultStart
        if let end = record?.endAt {
            draftEnd = end
            draftHasEnd = true
        } else {
            draftEnd = min(now, dayEnd(for: day))
            draftHasEnd = record?.startAt != nil
        }
        editingDay = EditingDay(date: day)
    }

    private struct EditingDay: Identifiable {
        let id = UUID()
        let date: Date
    }
}

#Preview {
    ContentView(syncStore: WatchSyncStore())
}
