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
                    Image(systemName: "books.vertical")
                }

            FavoritesView()
                .tabItem {
                    Image(systemName: "heart")
                }

            SubscriptionView()
                .tabItem {
                    Image(systemName: "storefront")
                }
        }
    }
}

#Preview {
    ContentView()
}
