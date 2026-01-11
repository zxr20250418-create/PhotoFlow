//
//  PhotoFlowWatchApp.swift
//  PhotoFlowWatch Watch App
//
//  Created by 郑鑫荣 on 2025/12/30.
//

import SwiftUI

@main
struct PhotoFlowWatch_Watch_AppApp: App {
    @StateObject private var syncStore = WatchSyncStore()
    var body: some Scene {
        WindowGroup {
            ContentView(syncStore: syncStore)
        }
    }
}
