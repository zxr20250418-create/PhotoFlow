//
//  PhotoFlowApp.swift
//  PhotoFlow
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import SwiftUI

@main
struct PhotoFlowApp: App {
    private let buildTag = "SAFE MODE BUILD 45aae13"

    init() {
        print("PF_BOOT_OK 45aae13")
    }

    var body: some Scene {
        WindowGroup {
            SafeModeView(
                buildTag: buildTag,
                onClearAndExit: clearLocalDataAndExit
            )
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

private struct SafeModeView: View {
    let buildTag: String
    let onClearAndExit: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("已进入安全模式")
                .font(.title2)
                .fontWeight(.semibold)
            Text(buildTag)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .padding(.vertical, 4)
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
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
