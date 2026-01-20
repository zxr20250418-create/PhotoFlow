//
//  ContentView.swift
//  PhotoFlow
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import Combine
import CloudKit
import CoreData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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

    fileprivate enum CanonicalKey {
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

    fileprivate enum EventKey {
        static let type = "type"
        static let eventType = "session_event"
        static let eventId = "eventId"
        static let sessionId = "sessionId"
        static let action = "action"
        static let clientAt = "clientAt"
        static let sourceDevice = "sourceDevice"
        static let ackForEventId = "ackForEventId"
    }

    struct CanonicalState: Codable, Equatable {
        let sessionId: String
        let stage: String
        let shootingStart: Date?
        let selectingStart: Date?
        let endedAt: Date?
        let updatedAt: Date
        let revision: Int64
        let sourceDevice: String
    }

    struct SessionEvent: Identifiable {
        let id: String
        let sessionId: String
        let action: String
        let clientAt: TimeInterval
        let sourceDevice: String
    }

    @Published var isOnDuty = false
    @Published var incomingEvent: SessionEvent?
    @Published var incomingCanonicalState: CanonicalState?
    @Published private(set) var canonicalState: CanonicalState?
    @Published var lastSyncAt: Date?
    @Published var pendingEventCount: Int = 0
    @Published var lastRevision: Int64 = 0
#if DEBUG
    @Published var debugLastSentPayload: String = "—"
    @Published var debugSessionStatus: String = "—"
#endif
    private let canonicalStorageKey = "pf_canonical_state_v1"
    private let processedEventIdsKey = "pf_sync_processed_event_ids_v1"
    private let processedEventLimit = 120
    private var processedEventIds: [String] = []
    private var processedEventIdSet: Set<String> = []
    private var pendingReplies: [String: ([String: Any]) -> Void] = [:]
    private var eventQueue: [SessionEvent] = []
    private var inFlightEventId: String?

    override init() {
        super.init()
        loadCanonicalState()
        loadProcessedEventIds()
        lastRevision = canonicalState?.revision ?? 0
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
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
        handlePayload(message, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handlePayload(message, replyHandler: replyHandler)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handlePayload(userInfo, replyHandler: nil)
    }

    private func handlePayload(_ payload: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        if let value = payload["isOnDuty"] as? Bool {
            isOnDuty = value
        }
        if let type = payload[CanonicalKey.type] as? String, type == CanonicalKey.requestType {
            sendLatestCanonicalState()
            return
        }
        if let canonical = decodeCanonicalState(from: payload) {
            mergeCanonicalState(canonical)
            return
        }
        guard let event = decodeSessionEvent(from: payload) else { return }
        enqueueEvent(event, replyHandler: replyHandler)
    }

    func reloadCanonicalState() -> CanonicalState? {
        loadCanonicalState()
        return canonicalState
    }

    func updateCanonicalState(_ state: CanonicalState, send: Bool) {
        applyCanonicalState(state)
        if send {
            sendCanonicalState(state)
        }
    }

    func nextRevision(now: Date) -> Int64 {
        let candidate = Int64(now.timeIntervalSince1970 * 1000)
        let current = max(canonicalState?.revision ?? 0, lastRevision)
        return max(candidate, current + 1)
    }

    private func applyCanonicalState(_ state: CanonicalState) {
        canonicalState = state
        lastSyncAt = state.updatedAt
        lastRevision = state.revision
        saveCanonicalState()
    }

    private func sendLatestCanonicalState() {
        guard let canonicalState else { return }
        sendCanonicalState(canonicalState)
    }

    private func sendCanonicalState(_ state: CanonicalState) {
        guard WCSession.isSupported() else { return }
        var payload = encodeCanonicalState(state)
        payload["isOnDuty"] = isOnDuty
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
        session.transferUserInfo(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("WCSession sendMessage failed: \(error.localizedDescription)")
            }
        }
    }

    private func mergeCanonicalState(_ incoming: CanonicalState) {
        if shouldApplyState(incoming) {
            applyCanonicalState(incoming)
            incomingCanonicalState = incoming
        }
    }

    private func shouldApplyState(_ incoming: CanonicalState) -> Bool {
        guard let current = canonicalState else { return true }
        if incoming.revision > current.revision {
            return true
        }
        if incoming.revision < current.revision {
            return false
        }
        return sourcePriority(incoming.sourceDevice) > sourcePriority(current.sourceDevice)
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

    private func encodeCanonicalState(_ state: CanonicalState) -> [String: Any] {
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
        let stageStartAt: Date?
        switch state.stage {
        case StageSyncKey.stageSelecting:
            stageStartAt = state.selectingStart
        case StageSyncKey.stageShooting:
            stageStartAt = state.shootingStart
        default:
            stageStartAt = nil
        }
        let isRunning = state.stage != StageSyncKey.stageStopped
        payload[StageSyncKey.stage] = state.stage
        payload[StageSyncKey.isRunning] = isRunning
        if let stageStartAt {
            payload[StageSyncKey.startedAt] = stageStartAt.timeIntervalSince1970
        }
        payload[StageSyncKey.lastUpdatedAt] = state.updatedAt.timeIntervalSince1970
        return payload
    }

    private func decodeCanonicalState(from payload: [String: Any]) -> CanonicalState? {
        let type = payload[CanonicalKey.type] as? String
        let hasCanonicalType = type == CanonicalKey.canonicalType
        let hasSessionId = payload[CanonicalKey.sessionId] != nil
        let hasStage = payload[CanonicalKey.stage] != nil
        guard hasCanonicalType || (hasSessionId && hasStage) else { return nil }
        guard let sessionId = parseString(payload[CanonicalKey.sessionId]) else { return nil }
        let stage = payload[CanonicalKey.stage] as? String ?? StageSyncKey.stageStopped
        let revision = parseInt64(payload[CanonicalKey.revision]) ?? Int64(Date().timeIntervalSince1970 * 1000)
        let updatedAtSeconds = parseTimeInterval(payload[CanonicalKey.updatedAt]) ?? Date().timeIntervalSince1970
        return CanonicalState(
            sessionId: sessionId,
            stage: stage,
            shootingStart: parseTimeInterval(payload[CanonicalKey.shootingStart]).map { Date(timeIntervalSince1970: $0) },
            selectingStart: parseTimeInterval(payload[CanonicalKey.selectingStart]).map { Date(timeIntervalSince1970: $0) },
            endedAt: parseTimeInterval(payload[CanonicalKey.endedAt]).map { Date(timeIntervalSince1970: $0) },
            updatedAt: Date(timeIntervalSince1970: updatedAtSeconds),
            revision: revision,
            sourceDevice: payload[CanonicalKey.sourceDevice] as? String ?? "unknown"
        )
    }

    private func decodeSessionEvent(from payload: [String: Any]) -> SessionEvent? {
        guard let type = payload[EventKey.type] as? String, type == EventKey.eventType else { return nil }
        guard let action = parseString(payload[EventKey.action]) else { return nil }
        let clientAt = parseTimeInterval(payload[EventKey.clientAt]) ?? Date().timeIntervalSince1970
        let sessionId = parseString(payload[EventKey.sessionId]) ?? "session-\(Int(clientAt * 1000))"
        let sourceDevice = parseString(payload[EventKey.sourceDevice]) ?? "watch"
        let eventId = parseString(payload[EventKey.eventId]) ?? "\(sessionId)|\(action)|\(Int(clientAt * 1000))"
        return SessionEvent(
            id: eventId,
            sessionId: sessionId,
            action: action,
            clientAt: clientAt,
            sourceDevice: sourceDevice
        )
    }

    private func enqueueEvent(_ event: SessionEvent, replyHandler: (([String: Any]) -> Void)?) {
        if isEventProcessed(event.id), let state = canonicalState {
            if let replyHandler {
                replyHandler(ackPayload(for: event.id, state: state))
            } else {
                sendAck(for: event.id, state: state)
            }
            return
        }
        if let replyHandler {
            pendingReplies[event.id] = replyHandler
        }
        eventQueue.append(event)
        updatePendingEventCount()
        processNextEventIfNeeded()
    }

    private func processNextEventIfNeeded() {
        guard inFlightEventId == nil, let next = eventQueue.first else { return }
        inFlightEventId = next.id
        eventQueue.removeFirst()
        updatePendingEventCount()
        incomingEvent = next
    }

    func completeEvent(eventId: String, state: CanonicalState) {
        sendAck(for: eventId, state: state)
        markEventProcessed(eventId)
        if inFlightEventId == eventId {
            inFlightEventId = nil
        }
        updatePendingEventCount()
        processNextEventIfNeeded()
    }

    private func sendAck(for eventId: String, state: CanonicalState) {
        let payload = ackPayload(for: eventId, state: state)
        if let replyHandler = pendingReplies.removeValue(forKey: eventId) {
            replyHandler(payload)
            return
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func ackPayload(for eventId: String, state: CanonicalState) -> [String: Any] {
        var payload = encodeCanonicalState(state)
        payload[EventKey.ackForEventId] = eventId
        return payload
    }

    private func updatePendingEventCount() {
        pendingEventCount = eventQueue.count + (inFlightEventId == nil ? 0 : 1)
    }

    private func markEventProcessed(_ eventId: String) {
        guard !processedEventIdSet.contains(eventId) else { return }
        processedEventIds.append(eventId)
        processedEventIdSet.insert(eventId)
        if processedEventIds.count > processedEventLimit {
            let overflow = processedEventIds.count - processedEventLimit
            let removed = processedEventIds.prefix(overflow)
            removed.forEach { processedEventIdSet.remove($0) }
            processedEventIds.removeFirst(overflow)
        }
        saveProcessedEventIds()
    }

    private func isEventProcessed(_ eventId: String) -> Bool {
        processedEventIdSet.contains(eventId)
    }

    private func parseTimeInterval(_ value: Any?) -> TimeInterval? {
        if let seconds = value as? Double {
            return seconds
        }
        if let seconds = value as? Int {
            return TimeInterval(seconds)
        }
        if let seconds = value as? Int64 {
            return TimeInterval(seconds)
        }
        return nil
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

    private func loadCanonicalState() {
        guard let data = UserDefaults.standard.data(forKey: canonicalStorageKey),
              let decoded = try? JSONDecoder().decode(CanonicalState.self, from: data) else {
            return
        }
        canonicalState = decoded
        lastSyncAt = decoded.updatedAt
        lastRevision = decoded.revision
    }

    private func saveCanonicalState() {
        guard let canonicalState,
              let data = try? JSONEncoder().encode(canonicalState) else { return }
        UserDefaults.standard.set(data, forKey: canonicalStorageKey)
    }

    private func loadProcessedEventIds() {
        guard let data = UserDefaults.standard.data(forKey: processedEventIdsKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        processedEventIds = decoded
        processedEventIdSet = Set(decoded)
    }

    private func saveProcessedEventIds() {
        guard let data = try? JSONEncoder().encode(processedEventIds) else { return }
        UserDefaults.standard.set(data, forKey: processedEventIdsKey)
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
final class CloudDataStore: ObservableObject {
    struct SessionRecord: Identifiable, Equatable {
        let id: String
        let stage: String
        let shootingStart: Date?
        let selectingStart: Date?
        let endedAt: Date?
        let amountCents: Int?
        let shotCount: Int?
        let selectedCount: Int?
        let reviewNote: String?
        let revision: Int64
        let updatedAt: Date
        let sourceDevice: String
        let isVoided: Bool
        let isDeleted: Bool
    }

    struct ShiftRecordSnapshot: Equatable {
        let dayKey: String
        let startAt: Date?
        let endAt: Date?
        let revision: Int64
        let updatedAt: Date
        let sourceDevice: String
    }

    struct DayMemoSnapshot: Equatable {
        let dayKey: String
        let text: String?
        let revision: Int64
        let updatedAt: Date
        let sourceDevice: String
    }

    struct StageEventRecord: Identifiable, Equatable {
        let id: String
        let sessionId: String
        let action: String
        let stageOrder: Int
        let clientAt: Date
        let createdAt: Date
        let sourceDevice: String
        let processedAt: Date?
        let processedResult: String?
        let processedError: String?
    }

    @Published private(set) var sessionRecords: [SessionRecord] = []
    @Published private(set) var shiftRecords: [String: ShiftRecordSnapshot] = [:]
    @Published private(set) var dayMemos: [String: DayMemoSnapshot] = [:]
    @Published private(set) var stageEvents: [StageEventRecord] = []
    @Published private(set) var lastCloudSyncAt: Date?
    @Published private(set) var lastRevision: Int64 = 0
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isRefreshing: Bool = false
    @Published private(set) var storeCloudEnabled: Bool = false
    @Published private(set) var cloudAccountStatus: String = "unknown"
    @Published private(set) var storeLoadError: String?
    @Published private(set) var cloudSyncError: String?
    @Published private(set) var lastCloudError: String?
    @Published private(set) var lastRefreshStatus: String = "idle"
    @Published private(set) var lastRefreshError: String?
    @Published private(set) var cloudTestMemoCount: Int?
    @Published private(set) var cloudTestSessionCount: Int?
    @Published private(set) var isCloudEnabled: Bool = true

    private enum EntityName {
        static let session = "SessionRecord"
        static let shift = "ShiftRecord"
        static let memo = "DayMemo"
        static let stageEvent = "StageEvent"
    }

    static let cloudContainerIdentifier = "iCloud.com.zhengxinrong.PhotoFlow"
    static let cloudTestMemoPrefix = "cloud-test-memo-"
    static let cloudTestSessionPrefix = "cloud-test-session-"

    private static let defaultStage = "stopped"

    private enum SessionField {
        static let sessionId = "sessionId"
        static let stage = "stage"
        static let shootingStart = "shootingStart"
        static let selectingStart = "selectingStart"
        static let endedAt = "endedAt"
        static let amountCents = "amountCents"
        static let shotCount = "shotCount"
        static let selectedCount = "selectedCount"
        static let reviewNote = "reviewNote"
        static let revision = "revision"
        static let updatedAt = "updatedAt"
        static let sourceDevice = "sourceDevice"
        static let isVoided = "isVoided"
        static let legacyIsDeleted = "isDeleted"
        static let isDeleted = "deletedFlag"
    }

    private enum ShiftField {
        static let dayKey = "dayKey"
        static let startAt = "startAt"
        static let endAt = "endAt"
        static let revision = "revision"
        static let updatedAt = "updatedAt"
        static let sourceDevice = "sourceDevice"
    }

    private enum MemoField {
        static let dayKey = "dayKey"
        static let text = "text"
        static let revision = "revision"
        static let updatedAt = "updatedAt"
        static let sourceDevice = "sourceDevice"
    }

    private enum StageEventField {
        static let eventId = "eventId"
        static let sessionId = "sessionId"
        static let action = "action"
        static let stageOrder = "stageOrder"
        static let clientAt = "clientAt"
        static let createdAt = "createdAt"
        static let sourceDevice = "sourceDevice"
        static let processedAt = "processedAt"
        static let processedResult = "processedResult"
        static let processedError = "processedError"
    }

    let localSourceDevice: String
    private let container: NSPersistentCloudKitContainer
    private let context: NSManagedObjectContext
    private var cancellables: Set<AnyCancellable> = []
    private var activeCloudEvents: Set<UUID> = []
    private var blockedSessionIds: Set<String> = []

    struct TombstoneDebugInfo: Equatable {
        let recordsFound: Int
        let maxRevisionBefore: Int64
        let maxRevisionAfter: Int64
        let winnerDeleted: Bool
    }

    struct VoidDebugInfo: Equatable {
        let recordsFound: Int
        let maxRevisionBefore: Int64
        let maxRevisionAfter: Int64
        let winnerVoided: Bool
    }

    init() {
        localSourceDevice = CloudDataStore.deviceSource()
        let setup = Self.makeContainer()
        container = setup.container
        context = container.viewContext
        isCloudEnabled = setup.cloudEnabled
        storeCloudEnabled = setup.storeCloudEnabled
        if let error = setup.loadError {
            let detail = Self.formatError(error)
            storeLoadError = detail
            lastCloudError = detail
        }
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        observeRemoteChanges()
        observeCloudEvents()
        refreshAll()
    }

    func sessionRecord(for sessionId: String) -> SessionRecord? {
        sessionRecords.first { $0.id == sessionId }
    }

    func upsertSessionTiming(
        sessionId: String,
        stage: String,
        shootingStart: Date?,
        selectingStart: Date?,
        endedAt: Date?,
        revision: Int64? = nil,
        updatedAt: Date = Date(),
        sourceDevice: String? = nil
    ) {
        guard !sessionId.isEmpty else {
            assertionFailure("sessionId is required")
            return
        }
        if isSessionDeleted(sessionId) {
            return
        }
        let source = sourceDevice ?? localSourceDevice
        let record = fetchSessionManagedObject(sessionId: sessionId)
        let existingDeleted = boolValue(record, key: SessionField.isDeleted)
        if existingDeleted {
            return
        }
        let existingRevision = int64Value(record, key: SessionField.revision)
        let existingSource = stringValue(record, key: SessionField.sourceDevice, fallback: "unknown")
        let nextRevisionValue = revision ?? nextRevision(existing: existingRevision)
        guard shouldApply(
            incomingRevision: nextRevisionValue,
            incomingSource: source,
            existingRevision: existingRevision,
            existingSource: existingSource
        ) else { return }
        let target = record ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.session, into: context)
        target.setValue(sessionId, forKey: SessionField.sessionId)
        target.setValue(stage, forKey: SessionField.stage)
        target.setValue(shootingStart, forKey: SessionField.shootingStart)
        target.setValue(selectingStart, forKey: SessionField.selectingStart)
        target.setValue(endedAt, forKey: SessionField.endedAt)
        target.setValue(nextRevisionValue, forKey: SessionField.revision)
        target.setValue(updatedAt.timeIntervalSince1970, forKey: SessionField.updatedAt)
        target.setValue(source, forKey: SessionField.sourceDevice)
        let existingVoided = boolValue(record, key: SessionField.isVoided)
        if record == nil {
            target.setValue(false, forKey: SessionField.isVoided)
            setSessionDeleted(false, on: target)
        } else {
            target.setValue(existingVoided, forKey: SessionField.isVoided)
            setSessionDeleted(existingDeleted, on: target)
        }
        saveContext()
    }

    func updateSessionMeta(
        sessionId: String,
        meta: SessionMeta,
        revision: Int64? = nil,
        updatedAt: Date = Date(),
        sourceDevice: String? = nil
    ) {
        guard !sessionId.isEmpty else {
            assertionFailure("sessionId is required")
            return
        }
        if isSessionDeleted(sessionId) {
            return
        }
        let source = sourceDevice ?? localSourceDevice
        let record = fetchSessionManagedObject(sessionId: sessionId)
        let existingDeleted = boolValue(record, key: SessionField.isDeleted)
        if existingDeleted {
            return
        }
        let existingRevision = int64Value(record, key: SessionField.revision)
        let existingSource = stringValue(record, key: SessionField.sourceDevice, fallback: "unknown")
        let nextRevisionValue = revision ?? nextRevision(existing: existingRevision)
        guard shouldApply(
            incomingRevision: nextRevisionValue,
            incomingSource: source,
            existingRevision: existingRevision,
            existingSource: existingSource
        ) else { return }
        let target = record ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.session, into: context)
        target.setValue(sessionId, forKey: SessionField.sessionId)
        target.setValue(meta.amountCents, forKey: SessionField.amountCents)
        target.setValue(meta.shotCount, forKey: SessionField.shotCount)
        target.setValue(meta.selectedCount, forKey: SessionField.selectedCount)
        target.setValue(meta.reviewNote, forKey: SessionField.reviewNote)
        target.setValue(nextRevisionValue, forKey: SessionField.revision)
        target.setValue(updatedAt.timeIntervalSince1970, forKey: SessionField.updatedAt)
        target.setValue(source, forKey: SessionField.sourceDevice)
        let existingVoided = boolValue(record, key: SessionField.isVoided)
        if record == nil {
            target.setValue(Self.defaultStage, forKey: SessionField.stage)
            target.setValue(false, forKey: SessionField.isVoided)
            setSessionDeleted(false, on: target)
        } else {
            target.setValue(existingVoided, forKey: SessionField.isVoided)
            setSessionDeleted(existingDeleted, on: target)
        }
        saveContext()
    }

    func updateSessionVisibility(
        sessionId: String,
        isVoided: Bool? = nil,
        isDeleted: Bool? = nil,
        revision: Int64? = nil,
        updatedAt: Date = Date(),
        sourceDevice: String? = nil
    ) {
        guard !sessionId.isEmpty else {
            assertionFailure("sessionId is required")
            return
        }
        let incomingDeleted = (isDeleted == true)
        if !incomingDeleted && isSessionDeleted(sessionId) {
            return
        }
        let source = sourceDevice ?? localSourceDevice
        let record = fetchSessionManagedObject(sessionId: sessionId)
        let existingDeleted = boolValue(record, key: SessionField.isDeleted)
        if existingDeleted && !incomingDeleted {
            return
        }
        let existingRevision = int64Value(record, key: SessionField.revision)
        let existingSource = stringValue(record, key: SessionField.sourceDevice, fallback: "unknown")
        let nextRevisionValue = revision ?? nextRevision(existing: existingRevision)
        guard shouldApply(
            incomingRevision: nextRevisionValue,
            incomingSource: source,
            existingRevision: existingRevision,
            existingSource: existingSource
        ) else { return }
        let target = record ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.session, into: context)
        target.setValue(sessionId, forKey: SessionField.sessionId)
        let existingVoided = boolValue(record, key: SessionField.isVoided)
        target.setValue(isVoided ?? existingVoided, forKey: SessionField.isVoided)
        setSessionDeleted(isDeleted ?? existingDeleted, on: target)
        target.setValue(nextRevisionValue, forKey: SessionField.revision)
        target.setValue(updatedAt.timeIntervalSince1970, forKey: SessionField.updatedAt)
        target.setValue(source, forKey: SessionField.sourceDevice)
        if record == nil {
            target.setValue(Self.defaultStage, forKey: SessionField.stage)
        }
        saveContext()
    }

    func voidSession(
        sessionId: String,
        updatedAt: Date = Date(),
        revision: Int64? = nil,
        sourceDevice: String? = nil
    ) -> VoidDebugInfo {
        guard !sessionId.isEmpty else {
            assertionFailure("sessionId is required")
            return VoidDebugInfo(
                recordsFound: 0,
                maxRevisionBefore: 0,
                maxRevisionAfter: 0,
                winnerVoided: false
            )
        }
        let source = sourceDevice ?? localSourceDevice
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.session)
        request.predicate = NSPredicate(format: "%K == %@", SessionField.sessionId, sessionId)
        let objects = (try? context.fetch(request)) ?? []
        let maxRevision = objects.map { int64Value($0, key: SessionField.revision) }.max() ?? 0
        let nowMillis = Int64(updatedAt.timeIntervalSince1970 * 1000)
        let nextRevisionValue = revision ?? max(nowMillis + 10_000, maxRevision + 10_000)
        let targets: [NSManagedObject]
        if objects.isEmpty {
            let target = NSEntityDescription.insertNewObject(forEntityName: EntityName.session, into: context)
            target.setValue(sessionId, forKey: SessionField.sessionId)
            targets = [target]
        } else {
            targets = objects
        }
        for target in targets {
            let existingStage = stringValue(target, key: SessionField.stage, fallback: Self.defaultStage)
            let existingDeleted = boolValue(target, key: SessionField.isDeleted)
            target.setValue(sessionId, forKey: SessionField.sessionId)
            target.setValue(existingStage, forKey: SessionField.stage)
            target.setValue(true, forKey: SessionField.isVoided)
            setSessionDeleted(existingDeleted, on: target)
            target.setValue(nextRevisionValue, forKey: SessionField.revision)
            target.setValue(updatedAt.timeIntervalSince1970, forKey: SessionField.updatedAt)
            target.setValue(source, forKey: SessionField.sourceDevice)
        }
        saveContext()
        context.refreshAllObjects()
        let postObjects = (try? context.fetch(request)) ?? []
        let maxRevisionAfter = postObjects.map { int64Value($0, key: SessionField.revision) }.max() ?? nextRevisionValue
        let winner = selectPreferredObject(postObjects, revisionKey: SessionField.revision, sourceKey: SessionField.sourceDevice)
        let winnerVoided = boolValue(winner, key: SessionField.isVoided)
        return VoidDebugInfo(
            recordsFound: max(objects.count, postObjects.count),
            maxRevisionBefore: maxRevision,
            maxRevisionAfter: maxRevisionAfter,
            winnerVoided: winnerVoided
        )
    }

    func tombstoneSession(
        sessionId: String,
        updatedAt: Date = Date(),
        revision: Int64? = nil,
        sourceDevice: String? = nil
    ) -> TombstoneDebugInfo {
        guard !sessionId.isEmpty else {
            assertionFailure("sessionId is required")
            return TombstoneDebugInfo(
                recordsFound: 0,
                maxRevisionBefore: 0,
                maxRevisionAfter: 0,
                winnerDeleted: false
            )
        }
        let source = sourceDevice ?? localSourceDevice
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.session)
        request.predicate = NSPredicate(format: "%K == %@", SessionField.sessionId, sessionId)
        let objects = (try? context.fetch(request)) ?? []
        let maxRevision = objects.map { int64Value($0, key: SessionField.revision) }.max() ?? 0
        let nowMillis = Int64(updatedAt.timeIntervalSince1970 * 1000)
        let nextRevisionValue = revision ?? max(nowMillis + 10_000, maxRevision + 10_000)
        let targets: [NSManagedObject]
        if objects.isEmpty {
            let target = NSEntityDescription.insertNewObject(forEntityName: EntityName.session, into: context)
            target.setValue(sessionId, forKey: SessionField.sessionId)
            targets = [target]
        } else {
            targets = objects
        }
        for target in targets {
            let existingStage = stringValue(target, key: SessionField.stage, fallback: Self.defaultStage)
            let existingVoided = boolValue(target, key: SessionField.isVoided)
            target.setValue(sessionId, forKey: SessionField.sessionId)
            target.setValue(existingStage, forKey: SessionField.stage)
            target.setValue(existingVoided, forKey: SessionField.isVoided)
            setSessionDeleted(true, on: target)
            target.setValue(nextRevisionValue, forKey: SessionField.revision)
            target.setValue(updatedAt.timeIntervalSince1970, forKey: SessionField.updatedAt)
            target.setValue(source, forKey: SessionField.sourceDevice)
        }
        saveContext()
        context.refreshAllObjects()
        var postObjects = (try? context.fetch(request)) ?? []
        var maxRevisionAfter = postObjects.map { int64Value($0, key: SessionField.revision) }.max() ?? nextRevisionValue
        var winner = selectPreferredObject(postObjects, revisionKey: SessionField.revision, sourceKey: SessionField.sourceDevice)
        var winnerDeleted = boolValue(winner, key: SessionField.isDeleted)
        if !winnerDeleted {
            let retryRevision = max(maxRevisionAfter + 10_000, nextRevisionValue + 10_000)
            if postObjects.isEmpty {
                let target = NSEntityDescription.insertNewObject(forEntityName: EntityName.session, into: context)
                target.setValue(sessionId, forKey: SessionField.sessionId)
                postObjects = [target]
            }
            for target in postObjects {
                let existingStage = stringValue(target, key: SessionField.stage, fallback: Self.defaultStage)
                let existingVoided = boolValue(target, key: SessionField.isVoided)
                target.setValue(sessionId, forKey: SessionField.sessionId)
                target.setValue(existingStage, forKey: SessionField.stage)
                target.setValue(existingVoided, forKey: SessionField.isVoided)
                setSessionDeleted(true, on: target)
                target.setValue(retryRevision, forKey: SessionField.revision)
                target.setValue(updatedAt.timeIntervalSince1970, forKey: SessionField.updatedAt)
                target.setValue(source, forKey: SessionField.sourceDevice)
            }
            saveContext()
            context.refreshAllObjects()
            let finalObjects = (try? context.fetch(request)) ?? []
            maxRevisionAfter = finalObjects.map { int64Value($0, key: SessionField.revision) }.max() ?? retryRevision
            winner = selectPreferredObject(finalObjects, revisionKey: SessionField.revision, sourceKey: SessionField.sourceDevice)
            winnerDeleted = boolValue(winner, key: SessionField.isDeleted)
            postObjects = finalObjects
        }
        let recordsFound = max(objects.count, postObjects.count)
        if !winnerDeleted {
            let snapshot = postObjects.map { object in
                let rev = int64Value(object, key: SessionField.revision)
                let updated = doubleValue(object, key: SessionField.updatedAt)
                let source = stringValue(object, key: SessionField.sourceDevice, fallback: "unknown")
                let deleted = boolValue(object, key: SessionField.isDeleted)
                return "rev=\(rev) updated=\(updated) source=\(source) deleted=\(deleted)"
            }.joined(separator: " | ")
            print("Tombstone persist failed for \(sessionId): \(snapshot)")
        }
        if winnerDeleted {
            blockedSessionIds.insert(sessionId)
        } else {
            blockedSessionIds.remove(sessionId)
        }
        return TombstoneDebugInfo(
            recordsFound: recordsFound,
            maxRevisionBefore: maxRevision,
            maxRevisionAfter: maxRevisionAfter,
            winnerDeleted: winnerDeleted
        )
    }

    func upsertShiftRecord(
        dayKey: String,
        startAt: Date?,
        endAt: Date?,
        revision: Int64? = nil,
        updatedAt: Date = Date(),
        sourceDevice: String? = nil
    ) {
        guard !dayKey.isEmpty else {
            assertionFailure("dayKey is required")
            return
        }
        let source = sourceDevice ?? localSourceDevice
        let record = fetchShiftManagedObject(dayKey: dayKey)
        let existingRevision = int64Value(record, key: ShiftField.revision)
        let existingSource = stringValue(record, key: ShiftField.sourceDevice, fallback: "unknown")
        let nextRevisionValue = revision ?? nextRevision(existing: existingRevision)
        guard shouldApply(
            incomingRevision: nextRevisionValue,
            incomingSource: source,
            existingRevision: existingRevision,
            existingSource: existingSource
        ) else { return }
        let target = record ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.shift, into: context)
        target.setValue(dayKey, forKey: ShiftField.dayKey)
        target.setValue(startAt, forKey: ShiftField.startAt)
        target.setValue(endAt, forKey: ShiftField.endAt)
        target.setValue(nextRevisionValue, forKey: ShiftField.revision)
        target.setValue(updatedAt.timeIntervalSince1970, forKey: ShiftField.updatedAt)
        target.setValue(source, forKey: ShiftField.sourceDevice)
        saveContext()
    }

    func upsertDayMemo(
        dayKey: String,
        text: String?,
        revision: Int64? = nil,
        updatedAt: Date = Date(),
        sourceDevice: String? = nil
    ) {
        guard !dayKey.isEmpty else {
            assertionFailure("dayKey is required")
            return
        }
        let source = sourceDevice ?? localSourceDevice
        let record = fetchMemoManagedObject(dayKey: dayKey)
        let existingRevision = int64Value(record, key: MemoField.revision)
        let existingSource = stringValue(record, key: MemoField.sourceDevice, fallback: "unknown")
        let nextRevisionValue = revision ?? nextRevision(existing: existingRevision)
        guard shouldApply(
            incomingRevision: nextRevisionValue,
            incomingSource: source,
            existingRevision: existingRevision,
            existingSource: existingSource
        ) else { return }
        let target = record ?? NSEntityDescription.insertNewObject(forEntityName: EntityName.memo, into: context)
        target.setValue(dayKey, forKey: MemoField.dayKey)
        target.setValue(text, forKey: MemoField.text)
        target.setValue(nextRevisionValue, forKey: MemoField.revision)
        target.setValue(updatedAt.timeIntervalSince1970, forKey: MemoField.updatedAt)
        target.setValue(source, forKey: MemoField.sourceDevice)
        saveContext()
    }

    func createStageEvent(
        eventId: String,
        sessionId: String,
        action: String,
        stageOrder: Int,
        clientAt: Date,
        sourceDevice: String? = nil
    ) {
        guard !eventId.isEmpty, !sessionId.isEmpty else {
            assertionFailure("eventId and sessionId are required")
            return
        }
        if fetchStageEventManagedObject(eventId: eventId) != nil {
            return
        }
        let source = sourceDevice ?? localSourceDevice
        let target = NSEntityDescription.insertNewObject(forEntityName: EntityName.stageEvent, into: context)
        target.setValue(eventId, forKey: StageEventField.eventId)
        target.setValue(sessionId, forKey: StageEventField.sessionId)
        target.setValue(action, forKey: StageEventField.action)
        target.setValue(Int64(stageOrder), forKey: StageEventField.stageOrder)
        target.setValue(clientAt.timeIntervalSince1970, forKey: StageEventField.clientAt)
        target.setValue(Date().timeIntervalSince1970, forKey: StageEventField.createdAt)
        target.setValue(source, forKey: StageEventField.sourceDevice)
        saveContext()
    }

    func fetchPendingStageEvents() -> [StageEventRecord] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.stageEvent)
        request.predicate = NSPredicate(
            format: "%K == nil OR %K == ''",
            StageEventField.processedResult,
            StageEventField.processedResult
        )
        let objects = (try? context.fetch(request)) ?? []
        let mapped = objects.compactMap { object -> StageEventRecord? in
            guard let eventId = object.value(forKey: StageEventField.eventId) as? String,
                  let sessionId = object.value(forKey: StageEventField.sessionId) as? String,
                  !eventId.isEmpty,
                  !sessionId.isEmpty else { return nil }
            let clientAt = Date(timeIntervalSince1970: doubleValue(object, key: StageEventField.clientAt))
            let createdAt = Date(timeIntervalSince1970: doubleValue(object, key: StageEventField.createdAt))
            return StageEventRecord(
                id: eventId,
                sessionId: sessionId,
                action: stringValue(object, key: StageEventField.action, fallback: ""),
                stageOrder: intValue(object, key: StageEventField.stageOrder) ?? 0,
                clientAt: clientAt,
                createdAt: createdAt,
                sourceDevice: stringValue(object, key: StageEventField.sourceDevice, fallback: "unknown"),
                processedAt: nil,
                processedResult: nil,
                processedError: nil
            )
        }
        return mapped.sorted { lhs, rhs in
            if lhs.clientAt != rhs.clientAt {
                return lhs.clientAt < rhs.clientAt
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func markStageEventProcessed(
        eventId: String,
        processedAt: Date,
        result: String,
        error: String? = nil
    ) {
        guard let target = fetchStageEventManagedObject(eventId: eventId) else { return }
        target.setValue(processedAt.timeIntervalSince1970, forKey: StageEventField.processedAt)
        target.setValue(result, forKey: StageEventField.processedResult)
        target.setValue(error, forKey: StageEventField.processedError)
        saveContext()
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        do {
            try context.save()
            refreshAll()
        } catch {
            let detail = Self.formatError(error)
            cloudSyncError = detail
            lastCloudError = detail
            print("CloudDataStore save failed: \(detail)")
            context.rollback()
        }
    }

    private func refreshAll() {
        sessionRecords = fetchSessionRecords()
        shiftRecords = Dictionary(uniqueKeysWithValues: fetchShiftRecords().map { ($0.dayKey, $0) })
        dayMemos = Dictionary(uniqueKeysWithValues: fetchDayMemos().map { ($0.dayKey, $0) })
        stageEvents = fetchStageEvents()
        updateRevisionSnapshot()
        updateDeletedSnapshot()
    }

    private func updateDeletedSnapshot() {
        let deleted = sessionRecords.filter(\.isDeleted).map(\.id)
        blockedSessionIds.formUnion(deleted)
    }

    private func isSessionDeleted(_ sessionId: String) -> Bool {
        if blockedSessionIds.contains(sessionId) {
            return true
        }
        return sessionRecords.first { $0.id == sessionId }?.isDeleted ?? false
    }

    func refreshLocalCache() {
        refreshAll()
    }

    private func updateRevisionSnapshot() {
        let sessionMax = sessionRecords.map(\.revision).max() ?? 0
        let shiftMax = shiftRecords.values.map(\.revision).max() ?? 0
        let memoMax = dayMemos.values.map(\.revision).max() ?? 0
        lastRevision = max(sessionMax, max(shiftMax, memoMax))
    }

    private func observeRemoteChanges() {
        NotificationCenter.default.publisher(
            for: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            let timestamp = Date()
            print("CloudDataStore remote change notification received at \(timestamp)")
            self?.lastCloudSyncAt = timestamp
            self?.refreshAll()
        }
        .store(in: &cancellables)
    }

    private func observeCloudEvents() {
        NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] notification in
            guard let self,
                  let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            if event.endDate == nil {
                activeCloudEvents.insert(event.identifier)
            } else {
                activeCloudEvents.remove(event.identifier)
                lastCloudSyncAt = event.endDate ?? Date()
            }
            if let error = event.error {
                let detail = Self.formatError(error)
                cloudSyncError = detail
                lastCloudError = detail
            }
            pendingCount = activeCloudEvents.count
        }
        .store(in: &cancellables)
    }

    func forceCloudRefreshAsync() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefreshStatus = "refreshing"
        lastRefreshError = nil
        defer { isRefreshing = false }
        print("CloudDataStore force refresh requested")
        refreshAll()
        var errors: [Error] = []
        if !storeCloudEnabled {
            let error = NSError(
                domain: "CloudDataStore",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "storeCloudEnabled=false"]
            )
            errors.append(error)
        }
        if let error = await refreshAccountStatusAsync() {
            errors.append(error)
        }
        if let error = await fetchCloudDebugCountsAsync() {
            errors.append(error)
        }
        if errors.isEmpty {
            lastRefreshStatus = "success"
            lastRefreshError = nil
            cloudSyncError = nil
            lastCloudError = nil
        } else {
            let detail = errors.map { Self.formatError($0) }.joined(separator: " | ")
            lastRefreshStatus = "fail"
            lastRefreshError = detail
            cloudSyncError = detail
            lastCloudError = detail
        }
    }

    func resetLocalStoreAsync() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefreshStatus = "resetting"
        lastRefreshError = nil
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(returning: ResetResult(success: false, error: nil))
                    return
                }
                let output = self.performResetLocalStore()
                continuation.resume(returning: output)
            }
        }
        if result.success {
            lastRefreshStatus = "reset-success"
            lastRefreshError = nil
            storeCloudEnabled = true
            storeLoadError = nil
            lastCloudError = nil
        } else {
            let detail = result.error.map { Self.formatError($0) } ?? "unknown reset error"
            lastRefreshStatus = "reset-fail"
            lastRefreshError = detail
            storeCloudEnabled = false
            storeLoadError = detail
            lastCloudError = detail
        }
        isRefreshing = false
        refreshAll()
    }

    private struct ResetResult {
        let success: Bool
        let error: Error?
    }

    private func performResetLocalStore() -> ResetResult {
        let coordinator = container.persistentStoreCoordinator
        let stores = coordinator.persistentStores
        for store in stores {
            if let url = store.url {
                do {
                    try coordinator.remove(store)
                    try coordinator.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: store.options)
                    deleteStoreFiles(at: url)
                } catch {
                    return ResetResult(success: false, error: error)
                }
            }
        }
        let load = Self.loadStores(container: container)
        return ResetResult(success: load.success, error: load.error)
    }

    private func deleteStoreFiles(at url: URL) {
        let fm = FileManager.default
        let base = url.deletingPathExtension().path
        let candidates = [url.path, "\(base)-shm", "\(base)-wal"]
        for path in candidates {
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
    }

    private func refreshAccountStatusAsync() async -> Error? {
        let container = CKContainer(identifier: Self.cloudContainerIdentifier)
        do {
            let status = try await container.accountStatus()
            cloudAccountStatus = Self.accountStatusLabel(status)
            return nil
        } catch {
            let detail = Self.formatError(error)
            cloudSyncError = detail
            lastCloudError = detail
            cloudAccountStatus = "error"
            return error
        }
    }

    private func fetchCloudDebugCountsAsync() async -> Error? {
        guard storeCloudEnabled else {
            cloudTestMemoCount = nil
            cloudTestSessionCount = nil
            return nil
        }
        let container = CKContainer(identifier: Self.cloudContainerIdentifier)
        let database = container.privateCloudDatabase
        do {
            async let memoCount = queryCloudCountAsync(
                database: database,
                recordType: EntityName.memo,
                predicate: NSPredicate(format: "text CONTAINS %@", Self.cloudTestMemoPrefix)
            )
            async let sessionCount = queryCloudCountAsync(
                database: database,
                recordType: EntityName.session,
                predicate: NSPredicate(format: "sessionId BEGINSWITH %@", Self.cloudTestSessionPrefix)
            )
            let (memoValue, sessionValue) = try await (memoCount, sessionCount)
            cloudTestMemoCount = memoValue
            cloudTestSessionCount = sessionValue
            return nil
        } catch {
            let detail = Self.formatError(error)
            cloudSyncError = detail
            lastCloudError = detail
            return error
        }
    }

    private func queryCloudCountAsync(
        database: CKDatabase,
        recordType: String,
        predicate: NSPredicate
    ) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            let query = CKQuery(recordType: recordType, predicate: predicate)
            let operation = CKQueryOperation(query: query)
            operation.desiredKeys = []
            operation.resultsLimit = 200
            var count = 0
            operation.recordFetchedBlock = { _ in
                count += 1
            }
            operation.queryCompletionBlock = { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: count)
                }
            }
            database.add(operation)
        }
    }

    private static func accountStatusLabel(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "available"
        case .noAccount:
            return "noAccount"
        case .restricted:
            return "restricted"
        case .couldNotDetermine:
            return "couldNotDetermine"
        @unknown default:
            return "unknown"
        }
    }

    private static func formatError(_ error: Error) -> String {
        let nsError = error as NSError
        var components: [String] = ["\(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)"]
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            components.append("underlying=\(formatNSError(underlying))")
        }
        let userInfoPairs = formatUserInfoPairs(nsError.userInfo)
        if !userInfoPairs.isEmpty {
            components.append("userInfo: " + userInfoPairs.joined(separator: ", "))
        }
        return components.joined(separator: " | ")
    }

    private static func formatNSError(_ error: NSError) -> String {
        "\(error.domain)(\(error.code)): \(error.localizedDescription)"
    }

    private static func formatUserInfoPairs(_ userInfo: [String: Any]) -> [String] {
        let entries = userInfo.compactMap { key, value -> (String, Any)? in
            guard key != NSUnderlyingErrorKey else { return nil }
            return (key, value)
        }
        let sorted = entries.sorted { $0.0 < $1.0 }
        let filtered = sorted.filter { key, _ in
            key.contains("NSPersistentStore") || key.contains("CloudKit") || key.contains("CK") || key.contains("NSDetailedErrors")
        }
        let candidates = filtered.isEmpty ? sorted : filtered
        return candidates.prefix(3).map { key, value in
            "\(key)=\(formatUserInfoValue(value))"
        }
    }

    private static func formatUserInfoValue(_ value: Any) -> String {
        if let error = value as? NSError {
            return formatNSError(error)
        }
        if let error = value as? Error {
            return formatNSError(error as NSError)
        }
        if let errors = value as? [NSError] {
            return errors.prefix(2).map(formatNSError).joined(separator: "; ")
        }
        if let values = value as? [Any] {
            return values.prefix(2).map { String(describing: $0) }.joined(separator: "; ")
        }
        if let url = value as? URL {
            return url.path
        }
        return String(describing: value)
    }

    private func fetchSessionRecords() -> [SessionRecord] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.session)
        let objects = (try? context.fetch(request)) ?? []
        let deduped = dedupeObjects(
            objects,
            idKey: SessionField.sessionId,
            revisionKey: SessionField.revision,
            sourceKey: SessionField.sourceDevice
        )
        return deduped.values.compactMap { object in
            guard let sessionId = object.value(forKey: SessionField.sessionId) as? String,
                  !sessionId.isEmpty else { return nil }
            let stage = stringValue(object, key: SessionField.stage, fallback: Self.defaultStage)
            let updatedAtSeconds = doubleValue(object, key: SessionField.updatedAt)
            return SessionRecord(
                id: sessionId,
                stage: stage,
                shootingStart: object.value(forKey: SessionField.shootingStart) as? Date,
                selectingStart: object.value(forKey: SessionField.selectingStart) as? Date,
                endedAt: object.value(forKey: SessionField.endedAt) as? Date,
                amountCents: intValue(object, key: SessionField.amountCents),
                shotCount: intValue(object, key: SessionField.shotCount),
                selectedCount: intValue(object, key: SessionField.selectedCount),
                reviewNote: object.value(forKey: SessionField.reviewNote) as? String,
                revision: int64Value(object, key: SessionField.revision),
                updatedAt: Date(timeIntervalSince1970: updatedAtSeconds),
                sourceDevice: stringValue(object, key: SessionField.sourceDevice, fallback: "unknown"),
                isVoided: boolValue(object, key: SessionField.isVoided),
                isDeleted: boolValue(object, key: SessionField.isDeleted)
            )
        }
    }

    private func fetchShiftRecords() -> [ShiftRecordSnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.shift)
        let objects = (try? context.fetch(request)) ?? []
        let deduped = dedupeObjects(
            objects,
            idKey: ShiftField.dayKey,
            revisionKey: ShiftField.revision,
            sourceKey: ShiftField.sourceDevice
        )
        return deduped.values.compactMap { object in
            guard let dayKey = object.value(forKey: ShiftField.dayKey) as? String,
                  !dayKey.isEmpty else { return nil }
            let updatedAtSeconds = doubleValue(object, key: ShiftField.updatedAt)
            return ShiftRecordSnapshot(
                dayKey: dayKey,
                startAt: object.value(forKey: ShiftField.startAt) as? Date,
                endAt: object.value(forKey: ShiftField.endAt) as? Date,
                revision: int64Value(object, key: ShiftField.revision),
                updatedAt: Date(timeIntervalSince1970: updatedAtSeconds),
                sourceDevice: stringValue(object, key: ShiftField.sourceDevice, fallback: "unknown")
            )
        }
    }

    private func fetchDayMemos() -> [DayMemoSnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.memo)
        let objects = (try? context.fetch(request)) ?? []
        let deduped = dedupeObjects(
            objects,
            idKey: MemoField.dayKey,
            revisionKey: MemoField.revision,
            sourceKey: MemoField.sourceDevice
        )
        return deduped.values.compactMap { object in
            guard let dayKey = object.value(forKey: MemoField.dayKey) as? String,
                  !dayKey.isEmpty else { return nil }
            let updatedAtSeconds = doubleValue(object, key: MemoField.updatedAt)
            return DayMemoSnapshot(
                dayKey: dayKey,
                text: object.value(forKey: MemoField.text) as? String,
                revision: int64Value(object, key: MemoField.revision),
                updatedAt: Date(timeIntervalSince1970: updatedAtSeconds),
                sourceDevice: stringValue(object, key: MemoField.sourceDevice, fallback: "unknown")
            )
        }
    }

    private func fetchStageEvents() -> [StageEventRecord] {
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.stageEvent)
        let objects = (try? context.fetch(request)) ?? []
        return objects.compactMap { object in
            guard let eventId = object.value(forKey: StageEventField.eventId) as? String,
                  let sessionId = object.value(forKey: StageEventField.sessionId) as? String,
                  !eventId.isEmpty,
                  !sessionId.isEmpty else { return nil }
            let clientAt = Date(timeIntervalSince1970: doubleValue(object, key: StageEventField.clientAt))
            let createdAt = Date(timeIntervalSince1970: doubleValue(object, key: StageEventField.createdAt))
            let processedAtValue = doubleValue(object, key: StageEventField.processedAt)
            let processedAt = processedAtValue > 0 ? Date(timeIntervalSince1970: processedAtValue) : nil
            return StageEventRecord(
                id: eventId,
                sessionId: sessionId,
                action: stringValue(object, key: StageEventField.action, fallback: ""),
                stageOrder: intValue(object, key: StageEventField.stageOrder) ?? 0,
                clientAt: clientAt,
                createdAt: createdAt,
                sourceDevice: stringValue(object, key: StageEventField.sourceDevice, fallback: "unknown"),
                processedAt: processedAt,
                processedResult: object.value(forKey: StageEventField.processedResult) as? String,
                processedError: object.value(forKey: StageEventField.processedError) as? String
            )
        }
    }

    private func fetchSessionManagedObject(sessionId: String) -> NSManagedObject? {
        fetchUniqueManagedObject(
            entityName: EntityName.session,
            idKey: SessionField.sessionId,
            idValue: sessionId,
            revisionKey: SessionField.revision,
            sourceKey: SessionField.sourceDevice
        )
    }

    private func fetchShiftManagedObject(dayKey: String) -> NSManagedObject? {
        fetchUniqueManagedObject(
            entityName: EntityName.shift,
            idKey: ShiftField.dayKey,
            idValue: dayKey,
            revisionKey: ShiftField.revision,
            sourceKey: ShiftField.sourceDevice
        )
    }

    private func fetchMemoManagedObject(dayKey: String) -> NSManagedObject? {
        fetchUniqueManagedObject(
            entityName: EntityName.memo,
            idKey: MemoField.dayKey,
            idValue: dayKey,
            revisionKey: MemoField.revision,
            sourceKey: MemoField.sourceDevice
        )
    }

    private func fetchStageEventManagedObject(eventId: String) -> NSManagedObject? {
        guard !eventId.isEmpty else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.stageEvent)
        request.predicate = NSPredicate(format: "%K == %@", StageEventField.eventId, eventId)
        return (try? context.fetch(request))?.first
    }

    private func fetchUniqueManagedObject(
        entityName: String,
        idKey: String,
        idValue: String,
        revisionKey: String,
        sourceKey: String
    ) -> NSManagedObject? {
        guard !idValue.isEmpty else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "%K == %@", idKey, idValue)
        let objects = (try? context.fetch(request)) ?? []
        guard let winner = selectPreferredObject(objects, revisionKey: revisionKey, sourceKey: sourceKey) else {
            return nil
        }
        for object in objects where object != winner {
            context.delete(object)
        }
        return winner
    }

    private func dedupeObjects(
        _ objects: [NSManagedObject],
        idKey: String,
        revisionKey: String,
        sourceKey: String
    ) -> [String: NSManagedObject] {
        var winners: [String: NSManagedObject] = [:]
        var revisions: [String: Int64] = [:]
        var sources: [String: String] = [:]
        for object in objects {
            guard let id = object.value(forKey: idKey) as? String, !id.isEmpty else { continue }
            let revision = int64Value(object, key: revisionKey)
            let source = stringValue(object, key: sourceKey, fallback: "unknown")
            if let existingRevision = revisions[id], let existingSource = sources[id] {
                if shouldApply(
                    incomingRevision: revision,
                    incomingSource: source,
                    existingRevision: existingRevision,
                    existingSource: existingSource
                ) {
                    winners[id] = object
                    revisions[id] = revision
                    sources[id] = source
                }
            } else {
                winners[id] = object
                revisions[id] = revision
                sources[id] = source
            }
        }
        return winners
    }

    private func selectPreferredObject(
        _ objects: [NSManagedObject],
        revisionKey: String,
        sourceKey: String
    ) -> NSManagedObject? {
        var winner: NSManagedObject?
        var winnerRevision: Int64 = 0
        var winnerSource: String = "unknown"
        for object in objects {
            let revision = int64Value(object, key: revisionKey)
            let source = stringValue(object, key: sourceKey, fallback: "unknown")
            if winner == nil {
                winner = object
                winnerRevision = revision
                winnerSource = source
                continue
            }
            if shouldApply(
                incomingRevision: revision,
                incomingSource: source,
                existingRevision: winnerRevision,
                existingSource: winnerSource
            ) {
                winner = object
                winnerRevision = revision
                winnerSource = source
            }
        }
        return winner
    }

    private func nextRevision(existing: Int64) -> Int64 {
        let candidate = Int64(Date().timeIntervalSince1970 * 1000)
        return max(candidate, existing + 1)
    }

    private func shouldApply(
        incomingRevision: Int64,
        incomingSource: String,
        existingRevision: Int64,
        existingSource: String
    ) -> Bool {
        if incomingRevision > existingRevision {
            return true
        }
        if incomingRevision < existingRevision {
            return false
        }
        return sourcePriority(incomingSource) >= sourcePriority(existingSource)
    }

    private func sourcePriority(_ source: String) -> Int {
        switch source {
        case "phone":
            return 3
        case "ipad":
            return 2
        case "watch":
            return 1
        default:
            return 0
        }
    }

    private func int64Value(_ object: NSManagedObject?, key: String) -> Int64 {
        guard let object else { return 0 }
        if let value = object.value(forKey: key) as? Int64 {
            return value
        }
        if let value = object.value(forKey: key) as? NSNumber {
            return value.int64Value
        }
        return 0
    }

    private func intValue(_ object: NSManagedObject?, key: String) -> Int? {
        guard let object else { return nil }
        if let value = object.value(forKey: key) as? Int {
            return value
        }
        if let value = object.value(forKey: key) as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private func doubleValue(_ object: NSManagedObject?, key: String) -> Double {
        guard let object else { return 0 }
        if let value = object.value(forKey: key) as? Double {
            return value
        }
        if let value = object.value(forKey: key) as? NSNumber {
            return value.doubleValue
        }
        return 0
    }

    private func boolValue(_ object: NSManagedObject?, key: String) -> Bool {
        guard let object else { return false }
        if key == SessionField.isDeleted {
            if let value = object.primitiveValue(forKey: SessionField.isDeleted) as? Bool {
                return value
            }
            if let value = object.primitiveValue(forKey: SessionField.isDeleted) as? NSNumber {
                return value.boolValue
            }
        }
        if let value = object.value(forKey: key) as? Bool {
            return value
        }
        if let value = object.value(forKey: key) as? NSNumber {
            return value.boolValue
        }
        return false
    }

    private func setSessionDeleted(_ value: Bool, on object: NSManagedObject) {
        object.willChangeValue(forKey: SessionField.isDeleted)
        object.setPrimitiveValue(value, forKey: SessionField.isDeleted)
        object.setValue(value, forKey: SessionField.isDeleted)
        object.didChangeValue(forKey: SessionField.isDeleted)
    }

    private func stringValue(_ object: NSManagedObject?, key: String, fallback: String) -> String {
        guard let object else { return fallback }
        return (object.value(forKey: key) as? String) ?? fallback
    }

    private static func deviceSource() -> String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "phone"
    }

    private static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = base?.appendingPathComponent("PhotoFlow", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("PhotoFlowCloud.sqlite")
    }

    private static func makeContainer() -> (
        container: NSPersistentCloudKitContainer,
        cloudEnabled: Bool,
        storeCloudEnabled: Bool,
        loadError: Error?
    ) {
        let model = makeModel()
        let container = NSPersistentCloudKitContainer(name: "PhotoFlowCloud", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL())
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudContainerIdentifier
        )
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        let cloudLoad = loadStores(container: container)
        if cloudLoad.success {
            return (container, true, true, cloudLoad.error)
        }
        let fallback = NSPersistentCloudKitContainer(name: "PhotoFlowCloud", managedObjectModel: model)
        let fallbackDescription = NSPersistentStoreDescription(url: storeURL())
        fallbackDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        fallbackDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        fallbackDescription.shouldMigrateStoreAutomatically = true
        fallbackDescription.shouldInferMappingModelAutomatically = true
        fallback.persistentStoreDescriptions = [fallbackDescription]
        let fallbackLoad = loadStores(container: fallback)
        if !fallbackLoad.success {
            print("CloudDataStore fallback load failed.")
        }
        return (fallback, false, false, cloudLoad.error ?? fallbackLoad.error)
    }

    private static func loadStores(container: NSPersistentCloudKitContainer) -> (success: Bool, error: Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        DispatchQueue.global(qos: .userInitiated).async {
            container.loadPersistentStores { _, error in
                loadError = error
                semaphore.signal()
            }
        }
        let result = semaphore.wait(timeout: .now() + 30)
        if result == .timedOut {
            let timeoutError = NSError(
                domain: "CloudDataStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "load timed out"]
            )
            print("CloudDataStore load timed out.")
            return (false, timeoutError)
        }
        if let error = loadError {
            print("CloudDataStore load failed: \(error.localizedDescription)")
            return (false, error)
        }
        return (true, nil)
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let session = NSEntityDescription()
        session.name = EntityName.session
        session.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        session.properties = [
            attribute(SessionField.sessionId, type: .stringAttributeType, optional: true),
            attribute(SessionField.stage, type: .stringAttributeType, defaultValue: Self.defaultStage),
            attribute(SessionField.shootingStart, type: .dateAttributeType, optional: true),
            attribute(SessionField.selectingStart, type: .dateAttributeType, optional: true),
            attribute(SessionField.endedAt, type: .dateAttributeType, optional: true),
            attribute(SessionField.amountCents, type: .integer64AttributeType, optional: true),
            attribute(SessionField.shotCount, type: .integer64AttributeType, optional: true),
            attribute(SessionField.selectedCount, type: .integer64AttributeType, optional: true),
            attribute(SessionField.reviewNote, type: .stringAttributeType, optional: true),
            attribute(SessionField.revision, type: .integer64AttributeType, defaultValue: 0),
            attribute(SessionField.updatedAt, type: .doubleAttributeType, defaultValue: 0.0),
            attribute(SessionField.sourceDevice, type: .stringAttributeType, defaultValue: "unknown"),
            attribute(SessionField.isVoided, type: .booleanAttributeType, defaultValue: false),
            attribute(SessionField.isDeleted, type: .booleanAttributeType, defaultValue: false),
            attribute(SessionField.legacyIsDeleted, type: .booleanAttributeType, defaultValue: false)
        ]

        let shift = NSEntityDescription()
        shift.name = EntityName.shift
        shift.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        shift.properties = [
            attribute(ShiftField.dayKey, type: .stringAttributeType, optional: true),
            attribute(ShiftField.startAt, type: .dateAttributeType, optional: true),
            attribute(ShiftField.endAt, type: .dateAttributeType, optional: true),
            attribute(ShiftField.revision, type: .integer64AttributeType, defaultValue: 0),
            attribute(ShiftField.updatedAt, type: .doubleAttributeType, defaultValue: 0.0),
            attribute(ShiftField.sourceDevice, type: .stringAttributeType, defaultValue: "unknown")
        ]

        let memo = NSEntityDescription()
        memo.name = EntityName.memo
        memo.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        memo.properties = [
            attribute(MemoField.dayKey, type: .stringAttributeType, optional: true),
            attribute(MemoField.text, type: .stringAttributeType, optional: true),
            attribute(MemoField.revision, type: .integer64AttributeType, defaultValue: 0),
            attribute(MemoField.updatedAt, type: .doubleAttributeType, defaultValue: 0.0),
            attribute(MemoField.sourceDevice, type: .stringAttributeType, defaultValue: "unknown")
        ]

        let stageEvent = NSEntityDescription()
        stageEvent.name = EntityName.stageEvent
        stageEvent.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        stageEvent.properties = [
            attribute(StageEventField.eventId, type: .stringAttributeType, optional: true),
            attribute(StageEventField.sessionId, type: .stringAttributeType, optional: true),
            attribute(StageEventField.action, type: .stringAttributeType, optional: true),
            attribute(StageEventField.stageOrder, type: .integer64AttributeType, defaultValue: 0),
            attribute(StageEventField.clientAt, type: .doubleAttributeType, defaultValue: 0.0),
            attribute(StageEventField.createdAt, type: .doubleAttributeType, defaultValue: 0.0),
            attribute(StageEventField.sourceDevice, type: .stringAttributeType, defaultValue: "unknown"),
            attribute(StageEventField.processedAt, type: .doubleAttributeType, defaultValue: 0.0),
            attribute(StageEventField.processedResult, type: .stringAttributeType, optional: true),
            attribute(StageEventField.processedError, type: .stringAttributeType, optional: true)
        ]

        model.entities = [session, shift, memo, stageEvent]
        return model
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }
}

@MainActor
final class SessionMetaStore: ObservableObject {
    @Published private(set) var metas: [String: SessionMeta] = [:]
    private let cloudStore: CloudDataStore
    private var cancellables: Set<AnyCancellable> = []

    init(cloudStore: CloudDataStore) {
        self.cloudStore = cloudStore
        apply(records: cloudStore.sessionRecords)
        cloudStore.$sessionRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] records in
                self?.apply(records: records)
            }
            .store(in: &cancellables)
    }

    func meta(for id: String) -> SessionMeta {
        metas[id] ?? SessionMeta()
    }

    func update(_ meta: SessionMeta, for id: String) {
        cloudStore.updateSessionMeta(sessionId: id, meta: meta)
    }

    private func apply(records: [CloudDataStore.SessionRecord]) {
        var mapped: [String: SessionMeta] = [:]
        for record in records {
            let meta = SessionMeta(
                amountCents: record.amountCents,
                shotCount: record.shotCount,
                selectedCount: record.selectedCount,
                reviewNote: record.reviewNote
            )
            if !meta.isEmpty {
                mapped[record.id] = meta
            }
        }
        metas = mapped
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
    private let cloudStore: CloudDataStore
    private var cancellables: Set<AnyCancellable> = []
    private let calendar: Calendar
    private let formatter: DateFormatter

    init(cloudStore: CloudDataStore) {
        self.cloudStore = cloudStore
        calendar = Calendar(identifier: .iso8601)
        formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        apply(records: cloudStore.shiftRecords)
        cloudStore.$shiftRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] records in
                self?.apply(records: records)
            }
            .store(in: &cancellables)
    }

    func dayKey(for date: Date) -> String {
        formatter.string(from: date)
    }

    func record(for key: String) -> ShiftRecord? {
        records[key]
    }

    func upsert(_ record: ShiftRecord, for key: String) {
        if record.isEmpty {
            cloudStore.upsertShiftRecord(dayKey: key, startAt: nil, endAt: nil)
        } else {
            cloudStore.upsertShiftRecord(dayKey: key, startAt: record.startAt, endAt: record.endAt)
        }
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

    private func apply(records: [String: CloudDataStore.ShiftRecordSnapshot]) {
        var mapped: [String: ShiftRecord] = [:]
        for (key, record) in records {
            let value = ShiftRecord(startAt: record.startAt, endAt: record.endAt)
            if !value.isEmpty {
                mapped[key] = value
            }
        }
        self.records = mapped
    }
}

@MainActor
final class DailyMemoStore: ObservableObject {
    @Published private(set) var memos: [String: String] = [:]
    private let cloudStore: CloudDataStore
    private var cancellables: Set<AnyCancellable> = []
    private let formatter: DateFormatter

    init(cloudStore: CloudDataStore) {
        self.cloudStore = cloudStore
        let calendar = Calendar(identifier: .iso8601)
        formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        apply(records: cloudStore.dayMemos)
        cloudStore.$dayMemos
            .receive(on: RunLoop.main)
            .sink { [weak self] memos in
                self?.apply(records: memos)
            }
            .store(in: &cancellables)
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
            cloudStore.upsertDayMemo(dayKey: key, text: nil)
        } else {
            cloudStore.upsertDayMemo(dayKey: key, text: memo)
        }
    }

    private func apply(records: [String: CloudDataStore.DayMemoSnapshot]) {
        var mapped: [String: String] = [:]
        for (key, memo) in records {
            if let text = memo.text, !text.isEmpty {
                mapped[key] = text
            }
        }
        memos = mapped
    }
}

@MainActor
final class SessionVisibilityStore: ObservableObject {
    @Published private(set) var voidedIds: Set<String> = []
    @Published private(set) var deletedIds: Set<String> = []
    @Published private(set) var tombstoneDebug: [String: CloudDataStore.TombstoneDebugInfo] = [:]
    private let cloudStore: CloudDataStore
    private var cancellables: Set<AnyCancellable> = []

    init(cloudStore: CloudDataStore) {
        self.cloudStore = cloudStore
        apply(records: cloudStore.sessionRecords)
        cloudStore.$sessionRecords
            .receive(on: RunLoop.main)
            .sink { [weak self] records in
                self?.apply(records: records)
            }
            .store(in: &cancellables)
    }

    func isVoided(_ id: String) -> Bool {
        voidedIds.contains(id)
    }

    func isDeleted(_ id: String) -> Bool {
        deletedIds.contains(id)
    }

    func setVoided(_ id: String, isVoided: Bool, revision: Int64? = nil, updatedAt: Date = Date()) {
        guard !deletedIds.contains(id) else { return }
        cloudStore.updateSessionVisibility(
            sessionId: id,
            isVoided: isVoided,
            revision: revision,
            updatedAt: updatedAt
        )
    }

    @discardableResult
    func markDeleted(
        _ id: String,
        updatedAt: Date = Date(),
        revision: Int64? = nil
    ) -> CloudDataStore.TombstoneDebugInfo {
        let debug = cloudStore.tombstoneSession(sessionId: id, updatedAt: updatedAt, revision: revision)
        tombstoneDebug[id] = debug
        if debug.winnerDeleted {
            deletedIds.insert(id)
        } else {
            deletedIds.remove(id)
        }
        cloudStore.refreshLocalCache()
        return debug
    }

    @discardableResult
    func markVoided(
        _ id: String,
        updatedAt: Date = Date(),
        revision: Int64? = nil
    ) -> CloudDataStore.VoidDebugInfo {
        let debug = cloudStore.voidSession(sessionId: id, updatedAt: updatedAt, revision: revision)
        if debug.winnerVoided {
            voidedIds.insert(id)
        } else {
            voidedIds.remove(id)
        }
        cloudStore.refreshLocalCache()
        return debug
    }

    func tombstoneInfo(for id: String) -> CloudDataStore.TombstoneDebugInfo? {
        tombstoneDebug[id]
    }

    private func apply(records: [CloudDataStore.SessionRecord]) {
        let voided = records.filter { $0.isVoided }.map(\.id)
        let deleted = records.filter { $0.isDeleted }.map(\.id)
        voidedIds = Set(voided)
        deletedIds = Set(deleted)
    }
}

struct ContentView: View {
    enum Stage {
        case idle
        case shooting
        case selecting
        case ended
    }

    enum StageAction: String, CaseIterable, Identifiable {
        case startShooting = "startShooting"
        case startSelecting = "startSelecting"
        case end = "end"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .startShooting:
                return "拍摄"
            case .startSelecting:
                return "选片"
            case .end:
                return "结束"
            }
        }

        var stageOrder: Int {
            switch self {
            case .startShooting:
                return 1
            case .startSelecting:
                return 2
            case .end:
                return 3
            }
        }

        var targetStage: Stage {
            switch self {
            case .startShooting:
                return .shooting
            case .startSelecting:
                return .selecting
            case .end:
                return .ended
            }
        }
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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .home
    @State private var sessionSummaries: [SessionSummary] = []
    @StateObject private var cloudStore: CloudDataStore
    @StateObject private var metaStore: SessionMetaStore
    @StateObject private var timeOverrideStore: SessionTimeOverrideStore
    @StateObject private var manualSessionStore: ManualSessionStore
    @StateObject private var shiftRecordStore: ShiftRecordStore
    @StateObject private var dailyMemoStore: DailyMemoStore
    @StateObject private var sessionVisibilityStore: SessionVisibilityStore
    @State private var editingSession: EditingSession?
    @State private var timeEditingSession: TimeEditingSession?
    @State private var swipeDeleteCandidateId: String?
    @State private var pendingDeleteIds: Set<String> = []
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
    @State private var selectedIpadSessionId: String?
    @State private var ipadDashboardSnapshot = IpadDashboardSnapshot.empty
    @State private var ipadDashboardRange: StatsRange = .today
    @State private var ipadMemoSelectedKey = ""
    @State private var ipadMemoDraft = ""
    @State private var ipadMemoStatus: String?
    @State private var ipadMemoConflictNotice: String?
    @State private var ipadMemoLastRevision: Int64 = 0
    @State private var ipadMemoLastSource = ""
    @AppStorage("pf_debug_mode_enabled") private var debugModeEnabled = false
    @State private var debugTapCount = 0
    @State private var lastDebugTapAt: Date?
    @State private var isProcessingStageEvents = false
    @State private var lastProcessedStageEventAt: Date?
    @State private var lastStageEventProcessError: String?
    @State private var stageEventPollTask: Task<Void, Never>?
    @State private var showIpadSyncDebug = false
    @State private var isExportingFiles = false
    @State private var exportDocument = ExportDocument(data: Data())
    @State private var exportFilename = "PhotoFlow-export.json"
    @State private var exportStatus: String?
    @State private var isImportingFiles = false
    @State private var importPreview: ImportPreview?
    @State private var pendingImportBundle: ExportBundle?
    @State private var importStatus: String?
    @State private var importError: String?
#if DEBUG
    @State private var showDebugPanel = false
#endif
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @ObservedObject var syncStore: WatchSyncStore

    init(syncStore: WatchSyncStore) {
        self.syncStore = syncStore
        let cloud = CloudDataStore()
        _cloudStore = StateObject(wrappedValue: cloud)
        _metaStore = StateObject(wrappedValue: SessionMetaStore(cloudStore: cloud))
        _timeOverrideStore = StateObject(wrappedValue: SessionTimeOverrideStore())
        _manualSessionStore = StateObject(wrappedValue: ManualSessionStore())
        let shiftStore = ShiftRecordStore(cloudStore: cloud)
        _shiftRecordStore = StateObject(wrappedValue: shiftStore)
        _dailyMemoStore = StateObject(wrappedValue: DailyMemoStore(cloudStore: cloud))
        _sessionVisibilityStore = StateObject(wrappedValue: SessionVisibilityStore(cloudStore: cloud))
        let defaults = UserDefaults.standard
        let start = defaults.object(forKey: "pf_shift_start") as? Date
        let end = defaults.object(forKey: "pf_shift_end") as? Date
        _shiftStart = State(initialValue: start)
        _shiftEnd = State(initialValue: end)
        shiftStore.seedFromLegacy(start: start, end: end)
    }

    var body: some View {
        if isReadOnlyDevice {
            ipadSyncView
        } else {
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
        .sheet(isPresented: $showIpadSyncDebug) {
            ipadSyncView
        }
        .onReceive(ticker) { now = $0 }
        .onReceive(syncStore.$incomingEvent) { event in
            guard let event = event else { return }
            applySessionEvent(event)
        }
        .onReceive(syncStore.$incomingCanonicalState) { state in
            guard let state else { return }
            applyCanonicalState(state, shouldPrompt: false)
        }
        .onReceive(cloudStore.$sessionRecords) { records in
            syncSessionSummaries(from: records)
        }
        .onReceive(cloudStore.$stageEvents) { _ in
            guard !isReadOnlyDevice else { return }
            processStageEvents(trigger: "stageEvents")
            startStageEventPolling()
        }
        .onReceive(dailyMemoStore.$memos) { memos in
            let dayKey = dailyMemoStore.dayKey(for: now)
            let latest = memos[dayKey] ?? ""
            if latest != memoDraft {
                memoDraft = latest
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                stageEventPollTask?.cancel()
                return
            }
            if isReadOnlyDevice {
                if let state = syncStore.reloadCanonicalState() {
                    applyCanonicalState(state, shouldPrompt: false)
                }
                return
            }
            if let state = syncStore.reloadCanonicalState() {
                applyCanonicalState(state, shouldPrompt: false)
                syncStore.updateCanonicalState(state, send: true)
            } else {
                syncStageState(now: now)
            }
            processStageEvents(trigger: "foreground")
            startStageEventPolling()
        }
        }
    }

    private func syncSessionSummaries(from records: [CloudDataStore.SessionRecord]) {
        let summaries = dedupedSessionRecords(records)
            .filter { $0.shootingStart != nil || $0.selectingStart != nil || $0.endedAt != nil }
            .map { record in
                SessionSummary(
                    id: record.id,
                    shootingStart: record.shootingStart,
                    selectingStart: record.selectingStart,
                    endedAt: record.endedAt
                )
            }
        sessionSummaries = summaries
    }

    private func dedupedSessionRecords(_ records: [CloudDataStore.SessionRecord]) -> [CloudDataStore.SessionRecord] {
        var winners: [String: CloudDataStore.SessionRecord] = [:]
        for record in records {
            if let existing = winners[record.id] {
                if record.revision > existing.revision {
                    winners[record.id] = record
                } else if record.revision == existing.revision {
                    if sourcePriority(record.sourceDevice) >= sourcePriority(existing.sourceDevice) {
                        winners[record.id] = record
                    }
                }
            } else {
                winners[record.id] = record
            }
        }
        return winners.values
            .filter { !$0.isDeleted && !$0.isVoided }
            .sorted { sessionSortKey(for: $0) < sessionSortKey(for: $1) }
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

    private var ipadSyncView: some View {
        let sessions = dedupedSessionRecords(cloudStore.sessionRecords)
        let sessionIds = sessions.map(\.id)
        let selectedRecord = sessions.first { $0.id == selectedIpadSessionId } ?? sessions.first
        return NavigationSplitView {
            List(sessions, selection: $selectedIpadSessionId) { record in
                ipadSessionRow(record: record)
                    .tag(record.id)
            }
            .listStyle(.sidebar)
            .navigationTitle("会话列表")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ipadStatsDashboard
                    if isReadOnlyDevice || isDebugBuild || debugModeEnabled {
                        ipadStageActionPanel(selectedRecord: selectedRecord)
                    }
                    Divider()
                    if sessions.isEmpty {
                        Text("暂无会话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let record = selectedRecord {
                        ipadSessionDetail(record: record)
                    } else {
                        Text("请选择会话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isReadOnlyDevice {
                        Divider()
                        ipadDayMemoEditor
                    }
                    ipadCloudStatusView
                    if isReadOnlyDevice {
                        filesTransferPanel
                    }
                    if shouldShowDebugControls {
                        ipadCloudDebugPanel(records: sessions)
                    }
                    ipadBuildFingerprintFooter
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("iPad Sync")
        }
        .onAppear {
            ipadDashboardRange = .today
            if selectedIpadSessionId == nil {
                selectedIpadSessionId = sessions.first?.id
            }
            refreshIpadDashboard(records: sessions, range: .today)
        }
        .onChange(of: sessionIds) { _, newIds in
            if let selected = selectedIpadSessionId, newIds.contains(selected) {
                refreshIpadDashboard(records: sessions, range: ipadDashboardRange)
                return
            }
            selectedIpadSessionId = newIds.first
            refreshIpadDashboard(records: sessions, range: ipadDashboardRange)
        }
        .onChange(of: ipadDashboardRange) { _, newRange in
            refreshIpadDashboard(records: sessions, range: newRange)
        }
        .onReceive(cloudStore.$sessionRecords) { records in
            let refreshed = dedupedSessionRecords(records)
            if let selected = selectedIpadSessionId,
               !refreshed.contains(where: { $0.id == selected }) {
                selectedIpadSessionId = refreshed.first?.id
            }
            refreshIpadDashboard(records: refreshed, range: ipadDashboardRange)
        }
    }

    private struct IpadDashboardSnapshot {
        let count: Int
        let totalDuration: TimeInterval
        let revenueCents: Int
        let hasRevenue: Bool
        let topRecords: [CloudDataStore.SessionRecord]

        static let empty = IpadDashboardSnapshot(
            count: 0,
            totalDuration: 0,
            revenueCents: 0,
            hasRevenue: false,
            topRecords: []
        )
    }

    private struct StageEventDiagnosticSnapshot {
        let pendingCount: Int
        let oldestPendingAge: TimeInterval?
        let lastProcessedAt: Date?
        let lastProcessError: String?
    }

    private func refreshIpadDashboard(records: [CloudDataStore.SessionRecord], range: StatsRange) {
        let isoCal = Calendar(identifier: .iso8601)
        let filtered = records.filter { record in
            guard let shootingStart = record.shootingStart else { return false }
            switch range {
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

        var totalDuration: TimeInterval = 0
        var revenueCents = 0
        var hasRevenue = false
        for record in filtered {
            totalDuration += cloudSessionDurations(for: record).total
            if let amount = record.amountCents {
                revenueCents += amount
                hasRevenue = true
            }
        }

        let sortedTopRecords = filtered.sorted { lhs, rhs in
            let left = lhs.amountCents ?? -1
            let right = rhs.amountCents ?? -1
            if left != right {
                return left > right
            }
            return sessionSortKey(for: lhs) > sessionSortKey(for: rhs)
        }

        ipadDashboardSnapshot = IpadDashboardSnapshot(
            count: filtered.count,
            totalDuration: totalDuration,
            revenueCents: revenueCents,
            hasRevenue: hasRevenue,
            topRecords: Array(sortedTopRecords.prefix(3))
        )
    }

    private var ipadStatsDashboard: some View {
        let snapshot = ipadDashboardSnapshot
        let revenueText = snapshot.hasRevenue ? formatAmount(cents: snapshot.revenueCents) : "--"
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("统计看板")
                .font(.headline)
            Picker("范围", selection: $ipadDashboardRange) {
                ForEach(StatsRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text(ipadDashboardRange.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ipadStatItem(title: "收入", value: revenueText)
                    ipadStatItem(title: "单数", value: "\(snapshot.count)")
                    ipadStatItem(title: "总时长", value: format(snapshot.totalDuration))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Top3（收入·\(ipadDashboardRange.title)）")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if snapshot.topRecords.isEmpty {
                    Text("暂无记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(snapshot.topRecords.enumerated()), id: \.element.id) { index, record in
                        ipadTop3Row(record: record, rank: index + 1)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func ipadStatItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .monospacedDigit()
        }
    }

    private func ipadTop3Row(record: CloudDataStore.SessionRecord, rank: Int) -> some View {
        let timeText = sessionStart(for: record).map(formatSessionTime) ?? "--"
        let amountText = record.amountCents.map { formatAmount(cents: $0) } ?? "--"
        return Button {
            selectedIpadSessionId = record.id
        } label: {
            HStack(spacing: 8) {
                Text("#\(rank)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText)
                        .font(.caption)
                        .monospacedDigit()
                    Text(stageLabel(for: record.stage))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(amountText)
                    .font(.caption)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var ipadCloudStatusView: some View {
        let syncText = cloudStore.lastCloudSyncAt.map(formatSessionTimeWithSeconds) ?? "--"
        let diagnostics = stageEventDiagnosticSnapshot()
        let pendingText = String(diagnostics.pendingCount)
        let oldestAgeText = formatStageEventAge(diagnostics.oldestPendingAge)
        let lastProcessedText = diagnostics.lastProcessedAt.map(formatSessionTimeWithSeconds) ?? "--"
        let lastErrorText = diagnostics.lastProcessError ?? "—"
        return VStack(alignment: .leading, spacing: 2) {
            Text("lastCloudSyncAt \(syncText)")
            Text("lastRevision \(cloudStore.lastRevision)")
            Text("pendingEventCount \(pendingText) · oldestPendingAge \(oldestAgeText)")
            Text("lastProcessedEventAt \(lastProcessedText)")
            Text("lastProcessError \(lastErrorText)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .onTapGesture {
            registerDebugTap()
        }
    }

    private var ipadDayMemoEditor: some View {
        let todayKey = dailyMemoStore.dayKey(for: now)
        let keys = ipadMemoKeys(todayKey: todayKey)
        let selectedKey = ipadMemoSelectedKey.isEmpty ? todayKey : ipadMemoSelectedKey
        let snapshot = cloudStore.dayMemos[selectedKey]
        let revisionText = snapshot.map { String($0.revision) } ?? "--"
        let sourceText = snapshot?.sourceDevice ?? "--"
        return VStack(alignment: .leading, spacing: 8) {
            Text("DayMemo（可编辑）")
                .font(.headline)
            Picker(
                "日期",
                selection: Binding(
                    get: { ipadMemoSelectedKey.isEmpty ? todayKey : ipadMemoSelectedKey },
                    set: { ipadMemoSelectedKey = $0 }
                )
            ) {
                ForEach(keys, id: \.self) { key in
                    Text(key).tag(key)
                }
            }
            .pickerStyle(.menu)

            TextEditor(text: $ipadMemoDraft)
                .frame(minHeight: 100)
                .padding(6)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button("保存") {
                    saveIpadMemo(for: selectedKey)
                }
                .buttonStyle(.bordered)
                Text("revision \(revisionText) · \(sourceText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let notice = ipadMemoConflictNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let status = ipadMemoStatus {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if ipadMemoSelectedKey.isEmpty {
                setIpadMemoSelection(todayKey)
            }
        }
        .onChange(of: ipadMemoSelectedKey) { _, newKey in
            guard !newKey.isEmpty else { return }
            setIpadMemoSelection(newKey)
        }
        .onReceive(cloudStore.$dayMemos) { _ in
            syncIpadMemoDraft()
        }
    }

    private func ipadMemoKeys(todayKey: String) -> [String] {
        var keySet = Set(cloudStore.dayMemos.keys)
        keySet.insert(todayKey)
        return keySet.sorted(by: >)
    }

    private func setIpadMemoSelection(_ key: String) {
        ipadMemoSelectedKey = key
        let memo = dailyMemoStore.memo(for: key)
        ipadMemoDraft = memo
        ipadMemoStatus = nil
        ipadMemoConflictNotice = nil
        let snapshot = cloudStore.dayMemos[key]
        ipadMemoLastRevision = snapshot?.revision ?? 0
        ipadMemoLastSource = snapshot?.sourceDevice ?? ""
    }

    private func saveIpadMemo(for key: String) {
        guard !key.isEmpty else { return }
        dailyMemoStore.setMemo(ipadMemoDraft, for: key)
        ipadMemoStatus = "已保存"
        ipadMemoConflictNotice = nil
    }

    private func syncIpadMemoDraft() {
        let todayKey = dailyMemoStore.dayKey(for: now)
        let key = ipadMemoSelectedKey.isEmpty ? todayKey : ipadMemoSelectedKey
        guard !key.isEmpty else { return }
        let latestText = dailyMemoStore.memo(for: key)
        let latestRevision = cloudStore.dayMemos[key]?.revision ?? 0
        let latestSource = cloudStore.dayMemos[key]?.sourceDevice ?? ""
        let dirty = memoIsDirty(draft: ipadMemoDraft, stored: latestText)
        if !dirty {
            ipadMemoDraft = latestText
            ipadMemoConflictNotice = nil
        } else if latestRevision != ipadMemoLastRevision || latestSource != ipadMemoLastSource {
            ipadMemoConflictNotice = "提示：该备注已被其他设备更新"
        }
        ipadMemoLastRevision = latestRevision
        ipadMemoLastSource = latestSource
    }

    private func memoIsDirty(draft: String, stored: String) -> Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
            != stored.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var ipadBuildFingerprintFooter: some View {
        Text("buildFingerprint: \(buildFingerprintText)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var filesTransferPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件导入导出")
                .font(.headline)
            HStack(spacing: 12) {
                Button("Export to Files") {
                    prepareExport()
                }
                Button("Import from Files") {
                    importError = nil
                    importStatus = nil
                    isImportingFiles = true
                }
            }
            .buttonStyle(.bordered)

            if let exportStatus {
                Text(exportStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let importStatus {
                Text(importStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let importError {
                Text(importError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fileExporter(
            isPresented: $isExportingFiles,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                exportStatus = "导出成功：\(url.lastPathComponent)"
            case .failure(let error):
                exportStatus = "导出失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    importError = "未选择文件"
                    return
                }
                Task {
                    await prepareImport(from: url)
                }
            case .failure(let error):
                importError = "导入失败：\(error.localizedDescription)"
            }
        }
        .sheet(item: $importPreview) { preview in
            importPreviewSheet(preview)
        }
    }

    private func ipadCloudDebugPanel(records: [CloudDataStore.SessionRecord]) -> some View {
        let memoPrefix = CloudDataStore.cloudTestMemoPrefix
        let testMemos = cloudStore.dayMemos.values
            .filter { ($0.text ?? "").contains(memoPrefix) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let testSessions = records.filter { $0.id.hasPrefix(CloudDataStore.cloudTestSessionPrefix) }
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let storeCloudEnabledText = cloudStore.storeCloudEnabled ? "true" : "false"
        let cloudLoadEnabledText = cloudStore.isCloudEnabled ? "true" : "false"
        let accountStatusText = cloudStore.cloudAccountStatus
        let storeLoadErrorText = cloudStore.storeLoadError ?? "—"
        let cloudSyncErrorText = cloudStore.cloudSyncError ?? "—"
        let lastCloudErrorText = cloudStore.lastCloudError ?? "—"
        let refreshStatusText = cloudStore.lastRefreshStatus
        let refreshErrorText = cloudStore.lastRefreshError ?? "—"
        let cloudMemoCountText = cloudStore.cloudTestMemoCount.map(String.init) ?? "--"
        let cloudSessionCountText = cloudStore.cloudTestSessionCount.map(String.init) ?? "--"
        return VStack(alignment: .leading, spacing: 8) {
            Text("Debug Cloud Test")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Force Cloud Refresh") {
                Task {
                    await cloudStore.forceCloudRefreshAsync()
                }
            }
            .buttonStyle(.bordered)
            .disabled(cloudStore.isRefreshing)

            Button("Reset Local Store") {
                Task {
                    await cloudStore.resetLocalStoreAsync()
                }
            }
            .buttonStyle(.bordered)
            .disabled(cloudStore.isRefreshing)

            if cloudStore.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Refreshing...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !isReadOnlyDevice {
                HStack(spacing: 8) {
                    Button("Create Cloud Test Memo") {
                        createCloudTestMemo()
                    }
                    Button("Create Cloud Test Session") {
                        createCloudTestSession()
                    }
                }
                .buttonStyle(.bordered)
            } else {
                Text("iPad 只读：请在 iPhone 端创建测试记录")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if testMemos.isEmpty {
                Text("No cloud-test-memo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(testMemos.prefix(3), id: \.dayKey) { memo in
                    let text = memo.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Text("\(memo.dayKey) · \(text)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if testSessions.isEmpty {
                Text("No cloud-test-session")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("cloud-test-session ×\(testSessions.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("buildFingerprint: \(buildFingerprintText)")
                Text("bundleId: \(bundleId)")
                Text("cloudKitContainerIdentifier: \(CloudDataStore.cloudContainerIdentifier)")
                Text("storeCloudEnabled: \(storeCloudEnabledText)")
                Text("cloudLoadEnabled: \(cloudLoadEnabledText)")
                Text("CKAccountStatus: \(accountStatusText)")
                Text("storeLoadError: \(storeLoadErrorText)")
                Text("cloudSyncError: \(cloudSyncErrorText)")
                Text("lastCloudError: \(lastCloudErrorText)")
                Text("refreshStatus: \(refreshStatusText)")
                Text("refreshError: \(refreshErrorText)")
                Text("localCounts: memo \(testMemos.count) · session \(testSessions.count)")
                Text("cloudCounts: memo \(cloudMemoCountText) · session \(cloudSessionCountText)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func ipadStageActionPanel(selectedRecord: CloudDataStore.SessionRecord?) -> some View {
        let sessions = dedupedSessionRecords(cloudStore.sessionRecords)
        let activeRecord = activeIpadSessionRecord(from: sessions)
        let currentOrder = activeRecord.map(stageOrder(for:)) ?? 0
        let currentStageText = activeRecord.map { stageLabel(for: $0.stage) } ?? "未开始"
        let selectedIsHistory = selectedRecord != nil && selectedRecord?.id != activeRecord?.id
        let selectedEnded = selectedRecord?.endedAt != nil || (selectedRecord.map(stageOrder(for:)) ?? 0) >= 3
        let showHistoryNotice = selectedIsHistory && selectedEnded
        let diagnostics = stageEventDiagnosticSnapshot()
        let pendingText = String(diagnostics.pendingCount)
        let oldestText = formatStageEventAge(diagnostics.oldestPendingAge)
        let lastProcessedText = diagnostics.lastProcessedAt.map(formatSessionTimeWithSeconds) ?? "--"
        let lastErrorText = diagnostics.lastProcessError ?? "—"
        return VStack(alignment: .leading, spacing: 8) {
            Text("阶段推进")
                .font(.headline)
            Text("当前阶段：\(currentStageText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let activeRecord {
                let timeText = sessionStart(for: activeRecord).map(formatSessionTime) ?? "--"
                Text("当前单：\(timeText) · \(activeRecord.id)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let activeRecord {
                if showHistoryNotice {
                    Text("已选择历史单；阶段推进只作用于当前进行中单")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(StageAction.allCases) { action in
                        let sessionId = action == .startShooting ? nil : activeRecord.id
                        Button(action.title) {
                            if let sessionId {
                                createStageEvent(action: action, sessionId: sessionId)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(sessionId == nil || !isStageActionAllowed(action, currentOrder: currentOrder))
                    }
                }
            } else {
                Text("当前无进行中会话，历史单不可推进")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("新建一单并开始拍摄") {
                    let sessionId = makeSessionId(startedAt: now)
                    createStageEvent(action: .startShooting, sessionId: sessionId)
                }
                .buttonStyle(.borderedProminent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("pendingEventCount \(pendingText) · oldestPendingAge \(oldestText)")
                Text("lastProcessedEventAt \(lastProcessedText)")
                Text("lastProcessError \(lastErrorText)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var stageEventDiagnosticsView: some View {
        let diagnostics = stageEventDiagnosticSnapshot()
        let pendingText = String(diagnostics.pendingCount)
        let oldestText = formatStageEventAge(diagnostics.oldestPendingAge)
        let lastProcessedText = diagnostics.lastProcessedAt.map(formatSessionTimeWithSeconds) ?? "--"
        let lastErrorText = diagnostics.lastProcessError ?? "—"
        return VStack(alignment: .leading, spacing: 2) {
            Text("pendingEventCount \(pendingText) · oldestPendingAge \(oldestText)")
            Text("lastProcessedEventAt \(lastProcessedText)")
            Text("lastProcessError \(lastErrorText)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private func cloudSessionDurations(
        for record: CloudDataStore.SessionRecord
    ) -> (total: TimeInterval, shooting: TimeInterval, selecting: TimeInterval?) {
        guard let shootingStart = record.shootingStart else {
            return (0, 0, nil)
        }
        let endTime = record.endedAt ?? now
        let total = max(0, endTime.timeIntervalSince(shootingStart))

        let shooting: TimeInterval
        if let selectingStart = record.selectingStart {
            shooting = max(0, selectingStart.timeIntervalSince(shootingStart))
        } else if let endedAt = record.endedAt {
            shooting = max(0, endedAt.timeIntervalSince(shootingStart))
        } else {
            shooting = max(0, now.timeIntervalSince(shootingStart))
        }

        let selecting: TimeInterval?
        if let selectingStart = record.selectingStart {
            let selectingEnd = record.endedAt ?? now
            selecting = max(0, selectingEnd.timeIntervalSince(selectingStart))
        } else {
            selecting = nil
        }

        return (total, shooting, selecting)
    }

    private func sessionStart(for record: CloudDataStore.SessionRecord) -> Date? {
        [record.shootingStart, record.selectingStart, record.endedAt].compactMap { $0 }.min()
    }

    private func sessionSortKey(for record: CloudDataStore.SessionRecord) -> Date {
        sessionStart(for: record) ?? record.updatedAt
    }

    private func latestSessionRecord(for sessionId: String) -> CloudDataStore.SessionRecord? {
        let candidates = cloudStore.sessionRecords.filter { $0.id == sessionId }
        guard var winner = candidates.first else { return nil }
        for record in candidates.dropFirst() {
            if record.revision > winner.revision {
                winner = record
            } else if record.revision == winner.revision {
                if sourcePriority(record.sourceDevice) >= sourcePriority(winner.sourceDevice) {
                    winner = record
                }
            }
        }
        return winner
    }

    private func stageLabel(for stage: String) -> String {
        switch stage {
        case WatchSyncStore.StageSyncKey.stageShooting:
            return "拍摄中"
        case WatchSyncStore.StageSyncKey.stageSelecting:
            return "选片中"
        case WatchSyncStore.StageSyncKey.stageStopped:
            return "已结束"
        default:
            return stage
        }
    }

    private func shiftTimeText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return formatSessionTime(date)
    }

    private func ipadSessionRow(record: CloudDataStore.SessionRecord) -> some View {
        let timeText = sessionStart(for: record).map(formatSessionTime) ?? "--"
        let amountText = record.amountCents.map { formatAmount(cents: $0) } ?? "--"
        var counts: [String] = []
        if let shotCount = record.shotCount {
            counts.append("拍\(shotCount)")
        }
        if let selectedCount = record.selectedCount {
            counts.append("选\(selectedCount)")
        }
        let countsText = counts.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Text(stageLabel(for: record.stage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(amountText)
                    .font(.headline)
                    .monospacedDigit()
            }
            if !countsText.isEmpty {
                Text(countsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = record.reviewNote, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func ipadSessionDetail(record: CloudDataStore.SessionRecord) -> some View {
        let amountText = record.amountCents.map { formatAmount(cents: $0) } ?? "—"
        let shotText = record.shotCount.map(String.init) ?? "—"
        let selectedText = record.selectedCount.map(String.init) ?? "—"
        let noteText = record.reviewNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let tombstoneInfo = sessionVisibilityStore.tombstoneInfo(for: record.id)
        let recordsFoundText = tombstoneInfo.map { String($0.recordsFound) } ?? "--"
        let maxRevisionBeforeText = tombstoneInfo.map { String($0.maxRevisionBefore) } ?? "--"
        let maxRevisionAfterText = tombstoneInfo.map { String($0.maxRevisionAfter) } ?? "--"
        let winnerDeletedText = tombstoneInfo.map { $0.winnerDeleted ? "yes" : "no" } ?? (record.isDeleted ? "yes" : "no")
        return VStack(alignment: .leading, spacing: 8) {
            Text("会话详情")
                .font(.headline)
            GroupBox("基础") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ID: \(record.id)")
                        .font(.caption)
                    Text("阶段: \(stageLabel(for: record.stage))")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("时间") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("拍摄开始: \(shiftTimeText(record.shootingStart))")
                    Text("选片开始: \(shiftTimeText(record.selectingStart))")
                    Text("结束: \(shiftTimeText(record.endedAt))")
                }
                .font(.caption)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("结算") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("金额: \(amountText)")
                    Text("拍摄: \(shotText)")
                    Text("选片: \(selectedText)")
                }
                .font(.caption)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("备注") {
                Text(noteText?.isEmpty == false ? noteText ?? "" : "—")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("同步") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("revision: \(record.revision)")
                    Text("updatedAt: \(formatSessionTimeWithSeconds(record.updatedAt))")
                    Text("source: \(record.sourceDevice)")
                    Text("voided: \(record.isVoided ? "yes" : "no")")
                    Text("deleted: \(record.isDeleted ? "yes" : "no")")
                    Text("recordsFound: \(recordsFoundText)")
                    Text("maxRevisionBefore: \(maxRevisionBeforeText)")
                    Text("maxRevisionAfter: \(maxRevisionAfterText)")
                    Text("winnerDeleted: \(winnerDeletedText)")
                    Text("build: \(buildFingerprintText)")
                }
                .font(.caption2)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var homeView: some View {
        let swipeDeleteBinding = Binding<Bool>(
            get: { swipeDeleteCandidateId != nil },
            set: { isPresented in
                if !isPresented {
                    swipeDeleteCandidateId = nil
                }
            }
        )
        return NavigationStack {
            VStack(spacing: 12) {
                homeFixedHeader

                VStack(alignment: .leading, spacing: 8) {
                    Text("会话时间线")
                        .font(.headline)
                    if effectiveSessionSummaries.isEmpty {
                        Text("暂无记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        let displaySessions = Array(effectiveSessionSummaries.reversed())
                        List {
                            ForEach(Array(displaySessions.enumerated()), id: \.element.id) { displayIndex, summary in
                                let total = displaySessions.count
                                let order = total - displayIndex
                                sessionTimelineRow(summary: summary, order: order)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("作废") {
                                            performSwipeVoid(id: summary.id)
                                        }
                                        .tint(.orange)
                                        Button("删除", role: .destructive) {
                                            swipeDeleteCandidateId = summary.id
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                    pendingDeleteBanner
                    homeDebugFooter
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .confirmationDialog("删除本单？", isPresented: swipeDeleteBinding, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let id = swipeDeleteCandidateId {
                        _ = deleteSession(id: id, showPending: true)
                    }
                    swipeDeleteCandidateId = nil
                }
                Button("取消", role: .cancel) {
                    swipeDeleteCandidateId = nil
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text(buildFingerprintText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .opacity(0.6)
                    .padding(.leading, 4)
                    .padding(.bottom, 56)
            }
        }
    }

    private func sessionTimelineRow(summary: SessionSummary, order: Int) -> some View {
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

        return ZStack(alignment: .topTrailing) {
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

    private static let homeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()

    private static let exportTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let exportFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private var homeFixedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.homeDateFormatter.string(from: now))
                .font(.headline)
                .onTapGesture {
                    registerDebugTap()
                }
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

    private var homeDebugFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
#if DEBUG
                Button("Debug: Open iPad Sync") {
                    showIpadSyncDebug = true
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.vertical, 4)

                Button(showDebugPanel ? "Debug: Hide Details" : "Debug: Show Details") {
                    showDebugPanel.toggle()
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .padding(.vertical, 4)
#endif
                Spacer(minLength: 8)
                Text(buildFingerprintText)
                    .monospacedDigit()
            }

            if debugModeEnabled && !isReadOnlyDevice && !isDebugBuild {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Debug Mode")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Open iPad Sync") {
                            showIpadSyncDebug = true
                        }
                        Button("Create Cloud Test Memo") {
                            createCloudTestMemo()
                        }
                        Button("Create Cloud Test Session") {
                            createCloudTestSession()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

#if DEBUG
            if showDebugPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("lastSentPayload")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(syncStore.debugLastSentPayload)
                        .font(.caption2)
                        .textSelection(.enabled)

                    Text("lastSyncAt / pending / lastRevision")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(formatDebugSyncTime(syncStore.lastSyncAt)) · \(syncStore.pendingEventCount) · \(syncStore.lastRevision)")
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
            if debugModeEnabled || isDebugBuild {
                stageEventDiagnosticsView
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
        .opacity(0.6)
    }

    @ViewBuilder
    private var pendingDeleteBanner: some View {
        if !pendingDeleteIds.isEmpty {
            Text("删除处理中 \(pendingDeleteIds.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isSessionVisible(_ id: String) -> Bool {
        !sessionVisibilityStore.isDeleted(id) && !sessionVisibilityStore.isVoided(id)
    }

    private func forcedVisibilityRevision(at date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000) + 10_000
    }

    private func performSwipeVoid(id: String) {
        let now = Date()
        let revision = forcedVisibilityRevision(at: now)
        sessionSummaries.removeAll { $0.id == id }
        let debug = sessionVisibilityStore.markVoided(id, updatedAt: now, revision: revision)
        syncSessionSummaries(from: cloudStore.sessionRecords)
        if !debug.winnerVoided {
            activeAlert = .validation("作废失败：未持久化")
            syncSessionSummaries(from: cloudStore.sessionRecords)
        }
    }

    @discardableResult
    private func deleteSession(id: String, showPending: Bool = false) -> Bool {
        let now = Date()
        let revision = forcedVisibilityRevision(at: now)
        if let index = sessionSummaries.firstIndex(where: { $0.id == id }),
           sessionSummaries[index].endedAt == nil {
            resetSession()
        }
        timeOverrideStore.clear(for: id)
        manualSessionStore.remove(id)
        if showPending {
            pendingDeleteIds.insert(id)
        }
        sessionSummaries.removeAll { $0.id == id }
        let debug = sessionVisibilityStore.markDeleted(id, updatedAt: now, revision: revision)
        syncSessionSummaries(from: cloudStore.sessionRecords)
        if showPending {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pendingDeleteIds.remove(id)
            }
        }
        if !debug.winnerDeleted {
            pendingDeleteIds.remove(id)
            activeAlert = .validation("Delete failed: tombstone not persisted")
            syncSessionSummaries(from: cloudStore.sessionRecords)
            return false
        }
        return true
    }


    private func sessionDetailView(summary: SessionSummary, order: Int) -> some View {
        let meta = metaStore.meta(for: summary.id)
        let times = effectiveTimes(for: summary)
        let startTime = times.shootingStart ?? effectiveSessionStartTime(for: summary)
        let timeText = startTime.map(formatSessionTime) ?? "--"
        let amountText = meta.amountCents.map { formatAmount(cents: $0) } ?? "--"
        let rphLine = rphText(for: summary)
        let hasOverride = timeOverrideStore.override(for: summary.id) != nil
        let record = latestSessionRecord(for: summary.id)
        let revisionText = record.map { String($0.revision) } ?? "--"
        let updatedText = record.map { formatSessionTimeWithSeconds($0.updatedAt) } ?? "--"
        let sourceText = record?.sourceDevice ?? "--"
        let deletedText = (record?.isDeleted ?? false) ? "yes" : "no"
        let voidedText = (record?.isVoided ?? false) ? "yes" : "no"
        let tombstoneInfo = sessionVisibilityStore.tombstoneInfo(for: summary.id)
        let recordsFoundText = tombstoneInfo.map { String($0.recordsFound) } ?? "--"
        let maxRevisionBeforeText = tombstoneInfo.map { String($0.maxRevisionBefore) } ?? "--"
        let maxRevisionAfterText = tombstoneInfo.map { String($0.maxRevisionAfter) } ?? "--"
        let winnerDeletedText = tombstoneInfo.map { $0.winnerDeleted ? "yes" : "no" } ?? deletedText
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
                    Text("同步")
                        .font(.headline)
                    HStack {
                        Text("revision")
                        Spacer()
                        Text(revisionText)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("updatedAt")
                        Spacer()
                        Text(updatedText)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("source")
                        Spacer()
                        Text(sourceText)
                    }
                    HStack {
                        Text("voided")
                        Spacer()
                        Text(voidedText)
                    }
                    HStack {
                        Text("deleted")
                        Spacer()
                        Text(deletedText)
                    }
                    HStack {
                        Text("recordsFound")
                        Spacer()
                        Text(recordsFoundText)
                    }
                    HStack {
                        Text("maxRevisionBefore")
                        Spacer()
                        Text(maxRevisionBeforeText)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("maxRevisionAfter")
                        Spacer()
                        Text(maxRevisionAfterText)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("winnerDeleted")
                        Spacer()
                        Text(winnerDeletedText)
                    }
                    HStack {
                        Text("build")
                        Spacer()
                        Text(buildFingerprintText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.footnote)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("单子详情")
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
        cloudStore.upsertSessionTiming(
            sessionId: sessionId,
            stage: WatchSyncStore.StageSyncKey.stageStopped,
            shootingStart: manual.shootingStart,
            selectingStart: manual.selectingStart,
            endedAt: manual.endedAt
        )
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
            if !isReadOnlyDevice {
                Divider()
                filesTransferPanel
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
                Text(effectiveOnDuty ? stageLabel : "未上班")
                    .font(.headline)
                nextActionButton
                if isReadOnlyDevice {
                    Text("只读模式")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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

    private var isReadOnlyDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var isDebugBuild: Bool {
#if DEBUG
        return true
#else
        return false
#endif
    }

    private var shouldShowDebugControls: Bool {
        debugModeEnabled
    }

    private let buildShortHashOverride = "fix158g"

    private var buildFingerprintText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "?"
        let rawHash = (info?["GitHash"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let overrideHash = buildShortHashOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortHash = rawHash.isEmpty ? (overrideHash.isEmpty ? nil : overrideHash) : String(rawHash.prefix(7))
        let versionText = "v\(shortVersion) (\(buildNumber))"
        let buildLabel = isDebugBuild ? "BUILD=DEBUG" : "BUILD=RELEASE"
        if let shortHash {
            return "\(buildLabel) · \(versionText) · \(shortHash)"
        }
        return "\(buildLabel) · \(versionText)"
    }

    private var effectiveOnDuty: Bool {
        if isReadOnlyDevice {
            return stage != .idle
        }
        return syncStore.isOnDuty
    }

    private var nextActionButton: some View {
        if effectiveOnDuty {
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
                .disabled(isReadOnlyDevice)
                .contextMenu {
                    if isReadOnlyDevice {
                        Button("只读模式") { }
                            .disabled(true)
                    } else {
                        Button("拍摄") { performStageAction(.shooting) }
                            .disabled(!canStartShooting)
                        Button("选片") { performStageAction(.selecting) }
                            .disabled(!canStartSelecting)
                        Button("结束") { performStageAction(.ended) }
                            .disabled(!canEndSession)
                        Button("下班", role: .destructive) { setDuty(false) }
                    }
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
            .disabled(isReadOnlyDevice)
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
        guard !isReadOnlyDevice else { return }
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
        guard !isReadOnlyDevice else { return }
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
        guard !isReadOnlyDevice else { return }
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
        syncStageState(now: now, sessionIdOverride: endedSessionId)
    }

    private func applySessionEvent(_ event: WatchSyncStore.SessionEvent) {
        let eventSeconds = normalizeEpochSeconds(event.clientAt)
        let eventTime = Date(timeIntervalSince1970: eventSeconds)
        let processedAt = Date()
        let sessionIdOverride = event.sessionId
        switch event.action {
        case "startShooting":
            session = Session()
            session.shootingStart = eventTime
            stage = .shooting
            updateSessionSummary(for: .shooting, at: eventTime, sessionIdOverride: sessionIdOverride)
        case "startSelecting":
            session.selectingStart = eventTime
            stage = .selecting
            updateSessionSummary(for: .selecting, at: eventTime, sessionIdOverride: sessionIdOverride)
        case "end":
            session.endedAt = eventTime
            stage = .ended
            let endedSessionId = activeSessionIndex().map { sessionSummaries[$0].id }
            updateSessionSummary(for: .ended, at: eventTime, sessionIdOverride: sessionIdOverride)
            let resolvedSessionId = endedSessionId ?? sessionIdOverride ?? sessionIdForTimestamp(eventTime)
            if let sessionId = resolvedSessionId {
                promptSettlementIfNeeded(for: sessionId)
            }
        default:
            break
        }
        let state = syncStageState(now: processedAt, sessionIdOverride: sessionIdOverride)
        syncStore.completeEvent(eventId: event.id, state: state)
    }

    private func applyCanonicalState(_ state: WatchSyncStore.CanonicalState, shouldPrompt: Bool) {
        let stageValue = state.stage
        let hasAnyTime = state.shootingStart != nil || state.selectingStart != nil || state.endedAt != nil
        let fallbackStart = state.shootingStart ?? state.selectingStart ?? state.endedAt
        let resolvedShootingStart = state.shootingStart ?? fallbackStart ?? (stageValue != WatchSyncStore.StageSyncKey.stageStopped ? state.updatedAt : nil)
        let resolvedSelectingStart = state.selectingStart ?? (stageValue == WatchSyncStore.StageSyncKey.stageSelecting ? state.updatedAt : nil)
        let resolvedEndedAt = state.endedAt ?? (stageValue == WatchSyncStore.StageSyncKey.stageStopped && resolvedShootingStart != nil ? state.updatedAt : nil)

        cloudStore.upsertSessionTiming(
            sessionId: state.sessionId,
            stage: state.stage,
            shootingStart: resolvedShootingStart,
            selectingStart: resolvedSelectingStart,
            endedAt: resolvedEndedAt,
            revision: state.revision,
            updatedAt: state.updatedAt,
            sourceDevice: state.sourceDevice
        )

        switch stageValue {
        case WatchSyncStore.StageSyncKey.stageShooting:
            stage = .shooting
        case WatchSyncStore.StageSyncKey.stageSelecting:
            stage = .selecting
        default:
            stage = hasAnyTime ? .ended : .idle
        }

        if stage == .idle {
            session = Session()
        } else {
            session.shootingStart = resolvedShootingStart
            session.selectingStart = resolvedSelectingStart
            session.endedAt = resolvedEndedAt
        }

        if resolvedShootingStart != nil || resolvedSelectingStart != nil || resolvedEndedAt != nil {
            upsertSessionSummary(
                sessionId: state.sessionId,
                shootingStart: resolvedShootingStart,
                selectingStart: resolvedSelectingStart,
                endedAt: resolvedEndedAt
            )
            if stage == .ended && shouldPrompt {
                promptSettlementIfNeeded(for: state.sessionId)
            }
        }
    }

    private func upsertSessionSummary(
        sessionId: String,
        shootingStart: Date?,
        selectingStart: Date?,
        endedAt: Date?
    ) {
        if let index = sessionSummaries.firstIndex(where: { $0.id == sessionId }) {
            var summary = sessionSummaries[index]
            if let shootingStart {
                if summary.shootingStart == nil || shootingStart < summary.shootingStart! {
                    summary.shootingStart = shootingStart
                }
            }
            if let selectingStart {
                if summary.selectingStart == nil || selectingStart < summary.selectingStart! {
                    summary.selectingStart = selectingStart
                }
            }
            if let endedAt {
                if summary.endedAt == nil || endedAt > summary.endedAt! {
                    summary.endedAt = endedAt
                }
            }
            sessionSummaries[index] = summary
        } else if shootingStart != nil || selectingStart != nil || endedAt != nil {
            sessionSummaries.append(SessionSummary(
                id: sessionId,
                shootingStart: shootingStart,
                selectingStart: selectingStart,
                endedAt: endedAt
            ))
        }
        sortSessionSummaries()
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

    private func formatDebugSyncTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm:ss"
        return formatter.string(from: date)
    }

    private func registerDebugTap() {
        guard !debugModeEnabled else { return }
        let now = Date()
        if let lastDebugTapAt, now.timeIntervalSince(lastDebugTapAt) > 1.5 {
            debugTapCount = 0
        }
        debugTapCount += 1
        lastDebugTapAt = now
        if debugTapCount >= 7 {
            debugModeEnabled = true
            debugTapCount = 0
        }
    }

    private func createCloudTestMemo() {
        let dayKey = dailyMemoStore.dayKey(for: now)
        let token = shortDebugToken()
        let text = "\(CloudDataStore.cloudTestMemoPrefix)\(token)"
        let revision = debugNowMillis()
        cloudStore.upsertDayMemo(dayKey: dayKey, text: text, revision: revision)
    }

    private func createCloudTestSession() {
        let token = shortDebugToken()
        let sessionId = "\(CloudDataStore.cloudTestSessionPrefix)\(token)"
        let revision = debugNowMillis()
        cloudStore.upsertSessionTiming(
            sessionId: sessionId,
            stage: WatchSyncStore.StageSyncKey.stageShooting,
            shootingStart: now,
            selectingStart: nil,
            endedAt: nil,
            revision: revision
        )
    }

    private func prepareExport() {
        importError = nil
        exportStatus = nil
        do {
            let bundle = makeExportBundle()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bundle)
            exportDocument = ExportDocument(data: data)
            exportFilename = exportFileName(for: now)
            isExportingFiles = true
        } catch {
            exportStatus = "导出失败：\(error.localizedDescription)"
        }
    }

    private func prepareImport(from url: URL) async {
        await MainActor.run {
            importError = nil
            importPreview = nil
            pendingImportBundle = nil
        }
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let bundle = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(ExportBundle.self, from: data)
            }.value
            guard bundle.schemaVersion == 1 else {
                throw NSError(
                    domain: "PhotoFlowExport",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "schemaVersion 不支持"]
                )
            }
            let deduped = dedupeEnvelopes(bundle.records)
            let normalized = ExportBundle(
                schemaVersion: bundle.schemaVersion,
                exportedAt: bundle.exportedAt,
                deviceId: bundle.deviceId,
                records: deduped
            )
            let preview = makeImportPreview(for: normalized)
            await MainActor.run {
                pendingImportBundle = normalized
                importPreview = preview
            }
        } catch {
            await MainActor.run {
                importError = "解析失败：\(error.localizedDescription)"
            }
        }
    }

    private func importPreviewSheet(_ preview: ImportPreview) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("导入预览")
                    .font(.headline)
                Text("总记录 \(preview.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("新增 \(preview.newCount) · 更新 \(preview.updateCount) · 跳过 \(preview.skipCount) · 冲突 \(preview.conflictCount)")
                    .font(.footnote)
                Text("冲突：revision 相等且 payload 不同。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Files Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        importPreview = nil
                        pendingImportBundle = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        applyImport(preview: preview)
                    }
                }
            }
        }
    }

    private func applyImport(preview: ImportPreview) {
        guard let bundle = pendingImportBundle else { return }
        let counts = applyImportBundle(bundle)
        importStatus = "导入完成：新增 \(counts.newCount) · 更新 \(counts.updateCount) · 跳过 \(counts.skipCount) · 冲突 \(counts.conflictCount)"
        importPreview = nil
        pendingImportBundle = nil
    }

    private func makeExportBundle() -> ExportBundle {
        let exportedAt = Self.exportTimestampFormatter.string(from: now)
        let records = exportRecords().sorted { lhs, rhs in
            if lhs.type == rhs.type {
                return lhs.key < rhs.key
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }
        return ExportBundle(
            schemaVersion: 1,
            exportedAt: exportedAt,
            deviceId: exportDeviceId(),
            records: records
        )
    }

    private func exportRecords() -> [RecordEnvelope] {
        var records: [RecordEnvelope] = []
        records.append(contentsOf: cloudStore.sessionRecords.map { record in
            let payload = RecordPayload(
                sessionId: record.id,
                stage: record.stage,
                shootingStart: record.shootingStart?.timeIntervalSince1970,
                selectingStart: record.selectingStart?.timeIntervalSince1970,
                endedAt: record.endedAt?.timeIntervalSince1970,
                amount: record.amountCents,
                shotCount: record.shotCount,
                selectedCount: record.selectedCount,
                reviewNote: record.reviewNote,
                isVoided: record.isVoided,
                isDeleted: record.isDeleted,
                dayKey: nil,
                startAt: nil,
                endAt: nil,
                text: nil
            )
            return RecordEnvelope(
                type: .session,
                key: record.id,
                revision: record.revision,
                updatedAt: record.updatedAt.timeIntervalSince1970,
                sourceDevice: record.sourceDevice,
                payload: payload
            )
        })
        records.append(contentsOf: cloudStore.shiftRecords.values.map { record in
            let payload = RecordPayload(
                sessionId: nil,
                stage: nil,
                shootingStart: nil,
                selectingStart: nil,
                endedAt: nil,
                amount: nil,
                shotCount: nil,
                selectedCount: nil,
                reviewNote: nil,
                isVoided: nil,
                isDeleted: nil,
                dayKey: record.dayKey,
                startAt: record.startAt?.timeIntervalSince1970,
                endAt: record.endAt?.timeIntervalSince1970,
                text: nil
            )
            return RecordEnvelope(
                type: .shift,
                key: record.dayKey,
                revision: record.revision,
                updatedAt: record.updatedAt.timeIntervalSince1970,
                sourceDevice: record.sourceDevice,
                payload: payload
            )
        })
        records.append(contentsOf: cloudStore.dayMemos.values.map { record in
            let payload = RecordPayload(
                sessionId: nil,
                stage: nil,
                shootingStart: nil,
                selectingStart: nil,
                endedAt: nil,
                amount: nil,
                shotCount: nil,
                selectedCount: nil,
                reviewNote: nil,
                isVoided: nil,
                isDeleted: nil,
                dayKey: record.dayKey,
                startAt: nil,
                endAt: nil,
                text: record.text
            )
            return RecordEnvelope(
                type: .memo,
                key: record.dayKey,
                revision: record.revision,
                updatedAt: record.updatedAt.timeIntervalSince1970,
                sourceDevice: record.sourceDevice,
                payload: payload
            )
        })
        return records
    }

    private func exportDeviceId() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? cloudStore.localSourceDevice
    }

    private func exportFileName(for date: Date) -> String {
        let stamp = Self.exportFilenameFormatter.string(from: date)
        return "PhotoFlow-export-\(stamp).json"
    }

    private func makeImportPreview(for bundle: ExportBundle) -> ImportPreview {
        let localSessions = Dictionary(uniqueKeysWithValues: cloudStore.sessionRecords.map { ($0.id, $0) })
        let localShifts = cloudStore.shiftRecords
        let localMemos = cloudStore.dayMemos
        var counts = ImportCounts()
        for envelope in bundle.records {
            guard !envelope.key.isEmpty else { continue }
            let decision: ImportDecision
            switch envelope.type {
            case .session:
                decision = importDecision(
                    envelope: envelope,
                    local: localSessions[envelope.key].map { local in
                        LocalRecordSnapshot(
                            revision: local.revision,
                            sourceDevice: local.sourceDevice,
                            payload: sessionPayload(from: local)
                        )
                    }
                )
            case .shift:
                decision = importDecision(
                    envelope: envelope,
                    local: localShifts[envelope.key].map { local in
                        LocalRecordSnapshot(
                            revision: local.revision,
                            sourceDevice: local.sourceDevice,
                            payload: shiftPayload(from: local)
                        )
                    }
                )
            case .memo:
                decision = importDecision(
                    envelope: envelope,
                    local: localMemos[envelope.key].map { local in
                        LocalRecordSnapshot(
                            revision: local.revision,
                            sourceDevice: local.sourceDevice,
                            payload: memoPayload(from: local)
                        )
                    }
                )
            }
            counts.totalCount += 1
            counts.conflictCount += decision.isConflict ? 1 : 0
            switch decision.action {
            case .new:
                counts.newCount += 1
            case .update:
                counts.updateCount += 1
            case .skip:
                counts.skipCount += 1
            }
        }
        return ImportPreview(
            totalCount: counts.totalCount,
            newCount: counts.newCount,
            updateCount: counts.updateCount,
            skipCount: counts.skipCount,
            conflictCount: counts.conflictCount
        )
    }

    private func applyImportBundle(_ bundle: ExportBundle) -> ImportCounts {
        let localSessions = Dictionary(uniqueKeysWithValues: cloudStore.sessionRecords.map { ($0.id, $0) })
        let localShifts = cloudStore.shiftRecords
        let localMemos = cloudStore.dayMemos
        var counts = ImportCounts()
        for envelope in bundle.records {
            guard !envelope.key.isEmpty else { continue }
            let decision: ImportDecision
            switch envelope.type {
            case .session:
                decision = importDecision(
                    envelope: envelope,
                    local: localSessions[envelope.key].map { local in
                        LocalRecordSnapshot(
                            revision: local.revision,
                            sourceDevice: local.sourceDevice,
                            payload: sessionPayload(from: local)
                        )
                    }
                )
            case .shift:
                decision = importDecision(
                    envelope: envelope,
                    local: localShifts[envelope.key].map { local in
                        LocalRecordSnapshot(
                            revision: local.revision,
                            sourceDevice: local.sourceDevice,
                            payload: shiftPayload(from: local)
                        )
                    }
                )
            case .memo:
                decision = importDecision(
                    envelope: envelope,
                    local: localMemos[envelope.key].map { local in
                        LocalRecordSnapshot(
                            revision: local.revision,
                            sourceDevice: local.sourceDevice,
                            payload: memoPayload(from: local)
                        )
                    }
                )
            }
            counts.totalCount += 1
            counts.conflictCount += decision.isConflict ? 1 : 0
            switch decision.action {
            case .new:
                counts.newCount += 1
                applyEnvelope(envelope, local: nil)
            case .update:
                counts.updateCount += 1
                applyEnvelope(envelope, local: localSessions[envelope.key])
            case .skip:
                counts.skipCount += 1
            }
        }
        return counts
    }

    private func importDecision(envelope: RecordEnvelope, local: LocalRecordSnapshot?) -> ImportDecision {
        guard let local else {
            return ImportDecision(action: .new, isConflict: false)
        }
        let incomingRevision = envelope.revision
        if incomingRevision > local.revision {
            return ImportDecision(action: .update, isConflict: false)
        }
        if incomingRevision < local.revision {
            return ImportDecision(action: .skip, isConflict: false)
        }
        let normalized = normalizedPayload(envelope.payload, type: envelope.type, key: envelope.key)
        let payloadDifferent = normalized != local.payload
        let incomingPriority = sourcePriority(envelope.sourceDevice)
        let localPriority = sourcePriority(local.sourceDevice)
        if payloadDifferent && incomingPriority > localPriority {
            return ImportDecision(action: .update, isConflict: true)
        }
        return ImportDecision(action: .skip, isConflict: payloadDifferent)
    }

    private func applyEnvelope(_ envelope: RecordEnvelope, local: CloudDataStore.SessionRecord?) {
        let updatedAt = Date(timeIntervalSince1970: envelope.updatedAt)
        let sourceDevice = envelope.sourceDevice.isEmpty ? "unknown" : envelope.sourceDevice
        let payload = normalizedPayload(envelope.payload, type: envelope.type, key: envelope.key)
        switch envelope.type {
        case .session:
            let sessionId = payload.sessionId ?? envelope.key
            guard !sessionId.isEmpty else { return }
            let stage = payload.stage ?? local?.stage ?? WatchSyncStore.StageSyncKey.stageStopped
            let shootingStart = payload.shootingStart.map { Date(timeIntervalSince1970: $0) }
            let selectingStart = payload.selectingStart.map { Date(timeIntervalSince1970: $0) }
            let endedAt = payload.endedAt.map { Date(timeIntervalSince1970: $0) }
            cloudStore.upsertSessionTiming(
                sessionId: sessionId,
                stage: stage,
                shootingStart: shootingStart,
                selectingStart: selectingStart,
                endedAt: endedAt,
                revision: envelope.revision,
                updatedAt: updatedAt,
                sourceDevice: sourceDevice
            )
            let meta = SessionMeta(
                amountCents: payload.amount,
                shotCount: payload.shotCount,
                selectedCount: payload.selectedCount,
                reviewNote: payload.reviewNote
            )
            cloudStore.updateSessionMeta(
                sessionId: sessionId,
                meta: meta,
                revision: envelope.revision,
                updatedAt: updatedAt,
                sourceDevice: sourceDevice
            )
            cloudStore.updateSessionVisibility(
                sessionId: sessionId,
                isVoided: payload.isVoided,
                isDeleted: payload.isDeleted,
                revision: envelope.revision,
                updatedAt: updatedAt,
                sourceDevice: sourceDevice
            )
        case .shift:
            let dayKey = payload.dayKey ?? envelope.key
            guard !dayKey.isEmpty else { return }
            let startAt = payload.startAt.map { Date(timeIntervalSince1970: $0) }
            let endAt = payload.endAt.map { Date(timeIntervalSince1970: $0) }
            cloudStore.upsertShiftRecord(
                dayKey: dayKey,
                startAt: startAt,
                endAt: endAt,
                revision: envelope.revision,
                updatedAt: updatedAt,
                sourceDevice: sourceDevice
            )
        case .memo:
            let dayKey = payload.dayKey ?? envelope.key
            guard !dayKey.isEmpty else { return }
            cloudStore.upsertDayMemo(
                dayKey: dayKey,
                text: payload.text,
                revision: envelope.revision,
                updatedAt: updatedAt,
                sourceDevice: sourceDevice
            )
        }
    }

    private func sessionPayload(from record: CloudDataStore.SessionRecord) -> RecordPayload {
        RecordPayload(
            sessionId: record.id,
            stage: record.stage,
            shootingStart: record.shootingStart?.timeIntervalSince1970,
            selectingStart: record.selectingStart?.timeIntervalSince1970,
            endedAt: record.endedAt?.timeIntervalSince1970,
            amount: record.amountCents,
            shotCount: record.shotCount,
            selectedCount: record.selectedCount,
            reviewNote: record.reviewNote,
            isVoided: record.isVoided,
            isDeleted: record.isDeleted,
            dayKey: nil,
            startAt: nil,
            endAt: nil,
            text: nil
        )
    }

    private func shiftPayload(from record: CloudDataStore.ShiftRecordSnapshot) -> RecordPayload {
        RecordPayload(
            sessionId: nil,
            stage: nil,
            shootingStart: nil,
            selectingStart: nil,
            endedAt: nil,
            amount: nil,
            shotCount: nil,
            selectedCount: nil,
            reviewNote: nil,
            isVoided: nil,
            isDeleted: nil,
            dayKey: record.dayKey,
            startAt: record.startAt?.timeIntervalSince1970,
            endAt: record.endAt?.timeIntervalSince1970,
            text: nil
        )
    }

    private func memoPayload(from record: CloudDataStore.DayMemoSnapshot) -> RecordPayload {
        RecordPayload(
            sessionId: nil,
            stage: nil,
            shootingStart: nil,
            selectingStart: nil,
            endedAt: nil,
            amount: nil,
            shotCount: nil,
            selectedCount: nil,
            reviewNote: nil,
            isVoided: nil,
            isDeleted: nil,
            dayKey: record.dayKey,
            startAt: nil,
            endAt: nil,
            text: record.text
        )
    }

    private func normalizedPayload(_ payload: RecordPayload, type: RecordType, key: String) -> RecordPayload {
        var normalized = payload
        switch type {
        case .session:
            if normalized.sessionId == nil {
                normalized.sessionId = key
            }
        case .shift, .memo:
            if normalized.dayKey == nil {
                normalized.dayKey = key
            }
        }
        return normalized
    }

    private func dedupeEnvelopes(_ records: [RecordEnvelope]) -> [RecordEnvelope] {
        var map: [String: RecordEnvelope] = [:]
        for record in records {
            let key = "\(record.type.rawValue)::\(record.key)"
            if let existing = map[key] {
                if record.revision > existing.revision {
                    map[key] = record
                } else if record.revision == existing.revision {
                    let incomingPriority = sourcePriority(record.sourceDevice)
                    let existingPriority = sourcePriority(existing.sourceDevice)
                    if incomingPriority > existingPriority {
                        map[key] = record
                    }
                }
            } else {
                map[key] = record
            }
        }
        return Array(map.values)
    }

    private func sourcePriority(_ source: String) -> Int {
        switch source.lowercased() {
        case "phone":
            return 3
        case "ipad", "pad":
            return 2
        case "watch":
            return 1
        default:
            return 0
        }
    }

    private func shortDebugToken() -> String {
        String(UUID().uuidString.prefix(6)).lowercased()
    }

    private func debugNowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func makeStageEventId() -> String {
        "stage-\(Int(now.timeIntervalSince1970 * 1000))-\(shortDebugToken())"
    }

    private func stageOrder(for stageValue: String, endedAt: Date?) -> Int {
        switch stageValue {
        case WatchSyncStore.StageSyncKey.stageShooting:
            return 1
        case WatchSyncStore.StageSyncKey.stageSelecting:
            return 2
        case WatchSyncStore.StageSyncKey.stageStopped:
            return endedAt == nil ? 0 : 3
        default:
            return endedAt == nil ? 0 : 3
        }
    }

    private func stageOrder(for record: CloudDataStore.SessionRecord) -> Int {
        stageOrder(for: record.stage, endedAt: record.endedAt)
    }

    private func stageOrderBySessionId(records: [CloudDataStore.SessionRecord]) -> [String: Int] {
        var map: [String: Int] = [:]
        for record in dedupedSessionRecords(records) {
            map[record.id] = stageOrder(for: record)
        }
        return map
    }

    private func pendingStageEvents() -> [CloudDataStore.StageEventRecord] {
        pendingStageEvents(events: cloudStore.stageEvents, records: cloudStore.sessionRecords)
    }

    private func pendingStageEvents(
        events: [CloudDataStore.StageEventRecord],
        records: [CloudDataStore.SessionRecord]
    ) -> [CloudDataStore.StageEventRecord] {
        let stageMap = stageOrderBySessionId(records: records)
        let pending = events.filter { event in
            let result = event.processedResult?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !result.isEmpty {
                return false
            }
            let currentOrder = stageMap[event.sessionId] ?? 0
            return currentOrder < event.stageOrder
        }
        return pending.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.clientAt < rhs.clientAt
        }
    }

    private func pendingStageEventCount() -> Int {
        pendingStageEvents().count
    }

    private func stageEventDiagnosticSnapshot() -> StageEventDiagnosticSnapshot {
        let pending = pendingStageEvents()
        let oldestPendingAge = pending.map(\.createdAt).min().map { now.timeIntervalSince($0) }
        let processedAtMax = cloudStore.stageEvents.compactMap(\.processedAt).max()
        let lastProcessedAt = [processedAtMax, lastProcessedStageEventAt].compactMap { $0 }.max()
        let lastErrorEvent = cloudStore.stageEvents
            .filter { ($0.processedError ?? "").isEmpty == false }
            .max { lhs, rhs in
                let left = lhs.processedAt ?? lhs.createdAt
                let right = rhs.processedAt ?? rhs.createdAt
                return left < right
            }
        let lastError = lastStageEventProcessError ?? lastErrorEvent?.processedError
        return StageEventDiagnosticSnapshot(
            pendingCount: pending.count,
            oldestPendingAge: oldestPendingAge,
            lastProcessedAt: lastProcessedAt,
            lastProcessError: lastError
        )
    }

    private func formatStageEventAge(_ age: TimeInterval?) -> String {
        guard let age, age > 0 else { return "--" }
        if age < 60 {
            return "\(Int(age))s"
        }
        if age < 3600 {
            return "\(Int(age / 60))m"
        }
        return "\(Int(age / 3600))h"
    }

    private func activeIpadSessionRecord(
        from records: [CloudDataStore.SessionRecord]
    ) -> CloudDataStore.SessionRecord? {
        let active = records.filter { $0.endedAt == nil && $0.stage != WatchSyncStore.StageSyncKey.stageStopped }
        return active.last
    }

    private func isStageActionAllowed(_ action: StageAction, currentOrder: Int) -> Bool {
        switch action {
        case .startShooting:
            return currentOrder == 0
        case .startSelecting:
            return currentOrder == 1
        case .end:
            return currentOrder == 1 || currentOrder == 2
        }
    }

    private func createStageEvent(action: StageAction, sessionId: String) {
        let eventId = makeStageEventId()
        cloudStore.createStageEvent(
            eventId: eventId,
            sessionId: sessionId,
            action: action.rawValue,
            stageOrder: action.stageOrder,
            clientAt: now
        )
    }

    private func applyStageAction(
        action: StageAction,
        eventTime: Date,
        sessionId: String
    ) {
        switch action {
        case .startShooting:
            session = Session()
            session.shootingStart = eventTime
            stage = .shooting
        case .startSelecting:
            session.shootingStart = session.shootingStart ?? eventTime
            session.selectingStart = eventTime
            stage = .selecting
        case .end:
            session.shootingStart = session.shootingStart ?? eventTime
            session.endedAt = eventTime
            stage = .ended
        }
        updateSessionSummary(for: action.targetStage, at: eventTime, sessionIdOverride: sessionId)
        if action == .end {
            promptSettlementIfNeeded(for: sessionId)
        }
    }

    private func processStageEvents(trigger: String) {
        let _ = trigger
        guard !isReadOnlyDevice, scenePhase == .active else { return }
        guard !isProcessingStageEvents else { return }
        let pending = cloudStore.fetchPendingStageEvents()
        guard !pending.isEmpty else { return }
        isProcessingStageEvents = true
        lastStageEventProcessError = nil
        var stageMap = stageOrderBySessionId(records: cloudStore.sessionRecords)
        for event in pending {
            let processedAt = Date()
            guard let action = StageAction(rawValue: event.action) else {
                let message = "rejected: unknown action \(event.action)"
                cloudStore.markStageEventProcessed(
                    eventId: event.id,
                    processedAt: processedAt,
                    result: "rejected",
                    error: message
                )
                lastProcessedStageEventAt = processedAt
                lastStageEventProcessError = message
                continue
            }
            if sessionVisibilityStore.isDeleted(event.sessionId) || sessionVisibilityStore.isVoided(event.sessionId) {
                let message = "rejected: session hidden"
                cloudStore.markStageEventProcessed(
                    eventId: event.id,
                    processedAt: processedAt,
                    result: "rejected",
                    error: message
                )
                lastProcessedStageEventAt = processedAt
                lastStageEventProcessError = message
                continue
            }
            let currentOrder = stageMap[event.sessionId] ?? 0
            if currentOrder >= 3 && action == .startShooting {
                let message = "rejected: ended session"
                cloudStore.markStageEventProcessed(
                    eventId: event.id,
                    processedAt: processedAt,
                    result: "rejected",
                    error: message
                )
                lastProcessedStageEventAt = processedAt
                lastStageEventProcessError = message
                continue
            }
            if !isStageActionAllowed(action, currentOrder: currentOrder) {
                let message = "rejected: invalid stageOrder \(action.stageOrder) for current \(currentOrder)"
                cloudStore.markStageEventProcessed(
                    eventId: event.id,
                    processedAt: processedAt,
                    result: "rejected",
                    error: message
                )
                lastProcessedStageEventAt = processedAt
                lastStageEventProcessError = message
                continue
            }
            if action.stageOrder <= currentOrder {
                let message = "rejected: stale stageOrder \(action.stageOrder) <= \(currentOrder)"
                cloudStore.markStageEventProcessed(
                    eventId: event.id,
                    processedAt: processedAt,
                    result: "rejected",
                    error: message
                )
                lastProcessedStageEventAt = processedAt
                lastStageEventProcessError = message
                continue
            }
            applyStageAction(action: action, eventTime: event.clientAt, sessionId: event.sessionId)
            _ = syncStageState(now: processedAt, sessionIdOverride: event.sessionId)
            cloudStore.markStageEventProcessed(
                eventId: event.id,
                processedAt: processedAt,
                result: "acked"
            )
            lastProcessedStageEventAt = processedAt
            stageMap[event.sessionId] = max(currentOrder, action.stageOrder)
        }
        isProcessingStageEvents = false
    }

    private func startStageEventPolling() {
        guard !isReadOnlyDevice else { return }
        guard isDebugBuild || debugModeEnabled else { return }
        stageEventPollTask?.cancel()
        guard pendingStageEventCount() > 0 else { return }
        stageEventPollTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                processStageEvents(trigger: "poll")
                if pendingStageEventCount() == 0 {
                    break
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func updateSessionSummary(for stage: Stage, at timestamp: Date, sessionIdOverride: String? = nil) {
        if let overrideId = sessionIdOverride,
           let index = sessionSummaries.firstIndex(where: { $0.id == overrideId }) {
            switch stage {
            case .shooting:
                let current = sessionSummaries[index].shootingStart
                if current == nil || timestamp < current! {
                    sessionSummaries[index].shootingStart = timestamp
                }
            case .selecting:
                let current = sessionSummaries[index].selectingStart
                if current == nil || timestamp < current! {
                    sessionSummaries[index].selectingStart = timestamp
                }
            case .ended:
                let current = sessionSummaries[index].endedAt
                if current == nil || timestamp > current! {
                    sessionSummaries[index].endedAt = timestamp
                }
            case .idle:
                break
            }
            sortSessionSummaries()
            return
        }

        if let index = targetSessionIndex(for: timestamp) {
            switch stage {
            case .shooting:
                let current = sessionSummaries[index].shootingStart
                if current == nil || timestamp < current! {
                    sessionSummaries[index].shootingStart = timestamp
                }
            case .selecting:
                let current = sessionSummaries[index].selectingStart
                if current == nil || timestamp < current! {
                    sessionSummaries[index].selectingStart = timestamp
                }
            case .ended:
                let current = sessionSummaries[index].endedAt
                if current == nil || timestamp > current! {
                    sessionSummaries[index].endedAt = timestamp
                }
            case .idle:
                break
            }
            sortSessionSummaries()
            return
        }

        switch stage {
        case .shooting:
            let sessionId = sessionIdOverride ?? makeSessionId(startedAt: timestamp)
            sessionSummaries.append(SessionSummary(
                id: sessionId,
                shootingStart: timestamp,
                selectingStart: nil,
                endedAt: nil
            ))
        case .selecting:
            guard let sessionId = sessionIdOverride else { return }
            sessionSummaries.append(SessionSummary(
                id: sessionId,
                shootingStart: nil,
                selectingStart: timestamp,
                endedAt: nil
            ))
        case .ended:
            guard let sessionId = sessionIdOverride else { return }
            sessionSummaries.append(SessionSummary(
                id: sessionId,
                shootingStart: nil,
                selectingStart: nil,
                endedAt: timestamp
            ))
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

    @discardableResult
    private func syncStageState(now: Date, sessionIdOverride: String? = nil) -> WatchSyncStore.CanonicalState {
        let state = makeCanonicalState(now: now, sessionIdOverride: sessionIdOverride)
        syncStore.updateCanonicalState(state, send: true)
        cloudStore.upsertSessionTiming(
            sessionId: state.sessionId,
            stage: state.stage,
            shootingStart: state.shootingStart,
            selectingStart: state.selectingStart,
            endedAt: state.endedAt,
            revision: state.revision,
            updatedAt: state.updatedAt,
            sourceDevice: state.sourceDevice
        )
        return state
    }

    private func makeCanonicalState(now: Date, sessionIdOverride: String?) -> WatchSyncStore.CanonicalState {
        let stageValue: String
        switch stage {
        case .shooting:
            stageValue = WatchSyncStore.StageSyncKey.stageShooting
        case .selecting:
            stageValue = WatchSyncStore.StageSyncKey.stageSelecting
        case .idle, .ended:
            stageValue = WatchSyncStore.StageSyncKey.stageStopped
        }
        let resolvedSessionId = resolveSessionId(now: now, sessionIdOverride: sessionIdOverride)
        return WatchSyncStore.CanonicalState(
            sessionId: resolvedSessionId,
            stage: stageValue,
            shootingStart: session.shootingStart,
            selectingStart: session.selectingStart,
            endedAt: session.endedAt,
            updatedAt: now,
            revision: syncStore.nextRevision(now: now),
            sourceDevice: "phone"
        )
    }

    private func resolveSessionId(now: Date, sessionIdOverride: String?) -> String {
        if let sessionIdOverride {
            return sessionIdOverride
        }
        if let activeIndex = activeSessionIndex() {
            return sessionSummaries[activeIndex].id
        }
        if let shootingStart = session.shootingStart, let id = sessionIdForTimestamp(shootingStart) {
            return id
        }
        if let selectingStart = session.selectingStart, let id = sessionIdForTimestamp(selectingStart) {
            return id
        }
        if let endedAt = session.endedAt, let id = sessionIdForTimestamp(endedAt) {
            return id
        }
        if stage == .idle {
            return "idle"
        }
        return makeSessionId(startedAt: session.shootingStart ?? now)
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

private enum RecordType: String, Codable {
    case session = "SessionRecord"
    case shift = "ShiftRecord"
    case memo = "DayMemo"
}

private struct RecordPayload: Codable, Equatable {
    var sessionId: String?
    var stage: String?
    var shootingStart: Double?
    var selectingStart: Double?
    var endedAt: Double?
    var amount: Int?
    var shotCount: Int?
    var selectedCount: Int?
    var reviewNote: String?
    var isVoided: Bool?
    var isDeleted: Bool?
    var dayKey: String?
    var startAt: Double?
    var endAt: Double?
    var text: String?
}

private struct RecordEnvelope: Codable {
    let type: RecordType
    let key: String
    let revision: Int64
    let updatedAt: Double
    let sourceDevice: String
    let payload: RecordPayload
}

private struct ExportBundle: Codable {
    let schemaVersion: Int
    let exportedAt: String
    let deviceId: String
    let records: [RecordEnvelope]
}

private struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ImportPreview: Identifiable {
    let id = UUID()
    let totalCount: Int
    let newCount: Int
    let updateCount: Int
    let skipCount: Int
    let conflictCount: Int
}

private struct ImportCounts {
    var totalCount: Int = 0
    var newCount: Int = 0
    var updateCount: Int = 0
    var skipCount: Int = 0
    var conflictCount: Int = 0
}

private enum ImportAction {
    case new
    case update
    case skip
}

private struct ImportDecision {
    let action: ImportAction
    let isConflict: Bool
}

private struct LocalRecordSnapshot {
    let revision: Int64
    let sourceDevice: String
    let payload: RecordPayload
}

#Preview {
    ContentView(syncStore: WatchSyncStore())
}
