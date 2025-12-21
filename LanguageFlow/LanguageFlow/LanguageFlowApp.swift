//
//  LanguageFlowApp.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 11/18/25.
//

import SwiftUI
import SwiftData

@main
struct LanguageFlowApp: App {
    @State private var authManager = AuthManager.shared
    @State private var toastManager = ToastManager.shared
    #if DEBUG
    @State private var showDebugPanel = false
    #endif

    init() {
        _ = IAPManager.shared
        Task {
            do {
                try await AuthManager.shared.syncUserStatus()
            } catch {
                print("[error] Initialization failed: \(error)")
            }
        }
        Task {
            SpeechModelManager.shared.prefetchIfNeeded()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                try? await AuthManager.shared.syncUserStatus()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .toastContainer(manager: toastManager)
                #if DEBUG
                .overlay(
                    ShakeDetector {
                        showDebugPanel = true
                    }
                    .allowsHitTesting(false)
                )
                .sheet(isPresented: $showDebugPanel) {
                    DebugPanelView(onDismiss: { showDebugPanel = false })
                }
                #endif
        }
        .modelContainer(for: [
            FavoritePodcast.self,
            FavoriteSegment.self,
            CompletedPodcast.self
        ])
    }
}
