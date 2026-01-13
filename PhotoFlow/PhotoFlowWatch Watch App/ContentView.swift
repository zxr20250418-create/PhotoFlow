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

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif

    func sessionReachabilityDidChange(_ session: WCSession) { }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let value = applicationContext["isOnDuty"] as? Bool else { return }
        Task { @MainActor in
            isOnDuty = value
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

    private enum DeepLinkStage: String {
        case shooting
        case selecting
        case stopped
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

#if DEBUG
            VStack(spacing: 6) {
                Button("DEBUG: stage/shooting") {
                    guard let url = URL(string: "photoflow://stage/shooting") else { return }
                    handleDeepLink(url)
                }
                Button("DEBUG: stage/selecting") {
                    guard let url = URL(string: "photoflow://stage/selecting") else { return }
                    handleDeepLink(url)
                }
                Button("DEBUG: stage/stopped") {
                    guard let url = URL(string: "photoflow://stage/stopped") else { return }
                    handleDeepLink(url)
                }
            }
            .font(.footnote)
#endif
        }
        .padding()
        .alert(item: $activeAlert) { alert in
            Alert(title: Text(alert.message))
        }
        .onReceive(ticker) { now = $0 }
        .onOpenURL { url in
            handleDeepLink(url)
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

    private func updateWidgetState(isRunning: Bool, startedAt: Date?, stage: String) {
        WidgetStateStore.writeState(isRunning: isRunning, startedAt: startedAt, stage: stage)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStateStore.widgetKind)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "photoflow", url.host == "stage" else { return }
        let components = url.pathComponents.filter { $0 != "/" }
        guard let stageComponent = components.first,
              let deepLinkStage = DeepLinkStage(rawValue: stageComponent) else { return }

        applyDeepLinkStage(deepLinkStage, now: Date())
    }

    private func applyDeepLinkStage(_ deepLinkStage: DeepLinkStage, now: Date) {
        switch deepLinkStage {
        case .shooting:
            stage = .shooting
            session.endedAt = nil
            session.selectingStart = nil
            if session.shootingStart == nil {
                session.shootingStart = now
            }
        case .selecting:
            stage = .selecting
            session.endedAt = nil
            if session.shootingStart == nil {
                session.shootingStart = now
            }
            if session.selectingStart == nil {
                session.selectingStart = now
            }
        case .stopped:
            stage = .ended
            if session.shootingStart != nil {
                session.endedAt = now
            } else {
                session.endedAt = nil
            }
        }
    }
}

#Preview {
    ContentView(syncStore: WatchSyncStore())
}

#if APP_EXTENSION
@main
struct PhotoFlowWatchExtensionApp: App {
    @StateObject private var syncStore = WatchSyncStore()

    var body: some Scene {
        WindowGroup {
            ContentView(syncStore: syncStore)
        }
    }
}
#endif
