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

    init() {
        Task {
            do {
                try await AuthManager.shared.syncUserStatus()
                await IAPManager.shared.loadProducts()
            } catch {
                print("[error] Initialization failed: \(error)")
            }
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
        }
        .modelContainer(for: [FavoritePodcast.self, FavoriteSegment.self])
    }
}
