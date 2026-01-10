//
//  ContentView.swift
//  PhotoFlow
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import SwiftUI

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

    @State private var isOnDuty = false
    @State private var stage: Stage = .idle
    @State private var session = Session()
    @State private var activeAlert: ActiveAlert?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let durations = computeDurations(now: now)

            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(isOnDuty ? stageLabel : "未上班")
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

                if stage == .shooting {
                    Button("尝试直接结束（应被拒绝）") {
                        activeAlert = .cannotEndWhileShooting
                    }
                    .buttonStyle(.bordered)
                }

                Button(isOnDuty ? "下班" : "上班") {
                    isOnDuty.toggle()
                    if !isOnDuty {
                        resetSession()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .alert(item: $activeAlert) { alert in
                Alert(title: Text(alert.message))
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
        if !isOnDuty {
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
        guard isOnDuty else {
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
            resetSession()
        }
    }

    private func resetSession() {
        stage = .idle
        session = Session()
    }

    private func computeDurations(now: Date) -> (total: TimeInterval, currentStage: TimeInterval) {
        let total: TimeInterval
        let currentStage: TimeInterval

        switch stage {
        case .idle:
            total = 0
            currentStage = 0
        case .shooting:
            guard let shootingStart = session.shootingStart else {
                return (0, 0)
            }
            total = max(0, now.timeIntervalSince(shootingStart))
            currentStage = total
        case .selecting:
            guard let shootingStart = session.shootingStart,
                  let selectingStart = session.selectingStart else {
                return (0, 0)
            }
            let shooting = max(0, selectingStart.timeIntervalSince(shootingStart))
            let selecting = max(0, now.timeIntervalSince(selectingStart))
            total = shooting + selecting
            currentStage = selecting
        case .ended:
            guard let shootingStart = session.shootingStart,
                  let selectingStart = session.selectingStart,
                  let endedAt = session.endedAt else {
                return (0, 0)
            }
            let shooting = max(0, selectingStart.timeIntervalSince(shootingStart))
            let selecting = max(0, endedAt.timeIntervalSince(selectingStart))
            total = shooting + selecting
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
}

#Preview {
    ContentView()
}
