//
//  PhotoFlowApp.swift
//  PhotoFlow
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import SwiftUI
import Combine
import UIKit

@main
struct PhotoFlowApp: App {
    @StateObject private var syncStore = WatchSyncStore()

    var body: some Scene {
        WindowGroup {
            BootGateRootView(syncStore: syncStore)
        }
    }
}

@MainActor
private final class AppBootGate: ObservableObject {
    enum State {
        case loading
        case ready(store: CloudDataStore, warning: String?)
        case safeMode(message: String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var lastBootError: String?
    @Published private(set) var bootModeDescription: String = "loading"

    private var didStart = false
    private var bootTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        state = .loading
        lastBootError = nil
        bootModeDescription = "loading"
        let lastRunAbnormal = RuntimeExitState.markLaunchStarted()
        runtimeLog("app", "launch", extra: [
            "abnormal_previous_exit": lastRunAbnormal ? "true" : "false"
        ])
        runtimeLog("boot", "store_boot_start")

        bootTask = Task { [weak self] in
            guard let self else { return }
            let result = await CloudDataStore.bootstrapWithFallback()
            guard !Task.isCancelled else { return }
            self.finishBoot(with: result)
        }

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.handleBootTimeout()
        }
    }

    func retry() {
        bootTask?.cancel()
        timeoutTask?.cancel()
        didStart = false
        startIfNeeded()
    }

    private func finishBoot(with result: CloudDataStore.BootResult) {
        timeoutTask?.cancel()
        switch result {
        case .ready(let store, let mode, let warning):
            if let warning, !warning.isEmpty {
                lastBootError = warning
            }
            bootModeDescription = mode.rawValue
            runtimeLog("boot", "store_boot_ok", extra: [
                "mode": mode.rawValue,
                "warning": warning ?? ""
            ])
            state = .ready(store: store, warning: warning)
        case .failed(let error):
            let fallback = error.isEmpty ? "启动失败，已进入安全模式。" : error
            lastBootError = fallback
            bootModeDescription = "safe-mode"
            runtimeLog("boot", "store_boot_fail", extra: [
                "error": fallback
            ])
            state = .safeMode(message: "启动失败，已进入安全模式。")
        }
        bootTask = nil
    }

    private func handleBootTimeout() {
        guard case .loading = state else { return }
        bootTask?.cancel()
        let timeoutMessage = "启动超过 5 秒未完成，已进入安全模式。"
        lastBootError = timeoutMessage
        bootModeDescription = "safe-mode-timeout"
        runtimeLog("boot", "store_boot_fail", extra: [
            "error": timeoutMessage
        ])
        state = .safeMode(message: timeoutMessage)
        timeoutTask = nil
    }
}

private struct BootGateRootView: View {
    @ObservedObject var syncStore: WatchSyncStore
    @StateObject private var bootGate = AppBootGate()

    var body: some View {
        Group {
            switch bootGate.state {
            case .loading:
                loadingView
            case .ready(let store, let warning):
                ContentView(
                    syncStore: syncStore,
                    cloudStore: store,
                    bootStateReady: true,
                    bootWarningMessage: warning
                )
            case .safeMode(let message):
                safeModeView(message: message)
            }
        }
        .task {
            bootGate.startIfNeeded()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在启动 PhotoFlow…")
                .font(.headline)
            Text("启动模式：\(bootGate.bootModeDescription)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = bootGate.lastBootError, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private func safeModeView(message: String) -> some View {
        VStack(spacing: 14) {
            Text("Safe Mode")
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
            if let error = bootGate.lastBootError, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            Button("复制启动错误") {
                UIPasteboard.general.string = bootGate.lastBootError ?? message
            }
            .buttonStyle(.bordered)
            Button("重试启动") {
                bootGate.retry()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }
}
