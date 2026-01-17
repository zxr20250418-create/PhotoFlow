//
//  PhotoFlowApp.swift
//  PhotoFlow
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import SwiftUI

@main
struct PhotoFlowApp: App {
    @AppStorage("pf_safe_mode") private var safeModeFlag = false

    private var safeModeEnabled: Bool {
        if ProcessInfo.processInfo.environment["PF_SAFE_MODE"] == "1" {
            return true
        }
        if safeModeFlag {
            return true
        }
#if DEBUG
        let forceSafeModeInDebug = true
        if forceSafeModeInDebug {
            return true
        }
#endif
        return false
    }

    var body: some Scene {
        WindowGroup {
            if safeModeEnabled {
                SafeModeView(
                    onClearAndExit: clearLocalDataAndExit,
                    onExitSafeMode: { safeModeFlag = false }
                )
            } else {
                RootContentView()
            }
        }
    }

    private func clearLocalDataAndExit() {
        clearLocalData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exit(0)
        }
    }

    private func clearLocalData() {
        let defaults = UserDefaults.standard
        if let bundleId = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleId)
        }
        defaults.synchronize()

        let manager = FileManager.default
        if let docs = manager.urls(for: .documentDirectory, in: .userDomainMask).first,
           let urls = try? manager.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for url in urls {
                try? manager.removeItem(at: url)
            }
        }
    }
}

private struct RootContentView: View {
    @StateObject private var syncStore = WatchSyncStore()

    var body: some View {
        ContentView(syncStore: syncStore)
    }
}

private struct SafeModeView: View {
    let onClearAndExit: () -> Void
    let onExitSafeMode: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("已进入安全模式")
                .font(.title2)
                .fontWeight(.semibold)
            Text("请先清空本地数据，再重新打开应用。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(role: .destructive) {
                onClearAndExit()
            } label: {
                Text("清空本地数据并退出")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button {
                onExitSafeMode()
            } label: {
                Text("退出安全模式")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Text("若设置了 PF_SAFE_MODE=1，请移除后再重启。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
