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

            FavoritePodcastsView()
                .tabItem {
                    Label("整篇", systemImage: "text.book.closed")
                }

            FavoriteSegmentsView()
                .tabItem {
                    Label("单句", systemImage: "text.quote")
                }
        }
    }
}

#Preview {
    ContentView()
}
