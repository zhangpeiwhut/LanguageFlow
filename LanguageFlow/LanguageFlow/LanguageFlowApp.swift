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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [FavoritePodcast.self, FavoriteSegment.self])
    }
}
