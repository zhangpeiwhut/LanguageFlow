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
                    Image(systemName: "radio")
                }

            FavoritePodcastsView()
                .tabItem {
                    Image(systemName: "bookmark")
                }

            FavoriteSegmentsView()
                .tabItem {
                    Image(systemName: "heart")
                }

            SubscriptionView()
                .tabItem {
                    Image(systemName: "flame")
                }
        }
    }
}

#Preview {
    ContentView()
}
