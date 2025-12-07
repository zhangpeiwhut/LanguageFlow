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
                    Image(systemName: "sailboat")
                }

            FavoritesView()
                .tabItem {
                    Image(systemName: "books.vertical")
                }

            SubscriptionView()
                .tabItem {
                    Image(systemName: "globe.asia.australia.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
