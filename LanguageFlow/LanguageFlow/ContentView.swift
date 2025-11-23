//
//  ContentView.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 11/18/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            FirstLevelView()
                .tabItem {
                    Label("频道", systemImage: "radio")
                }

            FavoritesView()
                .tabItem {
                    Label("收藏", systemImage: "heart.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
