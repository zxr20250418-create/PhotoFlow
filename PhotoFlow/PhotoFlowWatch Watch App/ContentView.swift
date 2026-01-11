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

@MainActor
final class WatchSyncStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isOnDuty = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
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

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }

    func sessionReachabilityDidChange(_ session: WCSession) { }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let value = applicationContext["isOnDuty"] as? Bool else { return }
        Task { @MainActor in
            isOnDuty = value
        }
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
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

            Button(action: handlePrimaryAction) {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .alert(item: $activeAlert) { alert in
            Alert(title: Text(alert.message))
        }
        .onReceive(ticker) { now = $0 }
        .onReceive(syncStore.$isOnDuty) { isOnDuty in
            if !isOnDuty {
                resetSession()
                updateWidgetState(isRunning: false, startedAt: nil)
            }
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
            updateWidgetState(isRunning: true, startedAt: now)
        case .shooting:
            stage = .selecting
            session.selectingStart = now
            syncStore.sendSessionEvent(event: "startSelecting", timestamp: now.timeIntervalSince1970)
            updateWidgetState(isRunning: true, startedAt: session.shootingStart)
        case .selecting:
            stage = .ended
            session.endedAt = now
            syncStore.sendSessionEvent(event: "end", timestamp: now.timeIntervalSince1970)
            updateWidgetState(isRunning: false, startedAt: nil)
        case .ended:
            session = Session()
            session.shootingStart = now
            stage = .shooting
            syncStore.sendSessionEvent(event: "startShooting", timestamp: now.timeIntervalSince1970)
            updateWidgetState(isRunning: true, startedAt: now)
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

    private func updateWidgetState(isRunning: Bool, startedAt: Date?) {
        WidgetStateStore.writeState(isRunning: isRunning, startedAt: startedAt, lastUpdatedAt: Date())
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStateStore.widgetKind)
        print("Widget state updated: running=\(isRunning)")
    }
}

#Preview {
    ContentView(syncStore: WatchSyncStore())
}
