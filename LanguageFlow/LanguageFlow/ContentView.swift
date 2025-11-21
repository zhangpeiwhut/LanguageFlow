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
            ChannelListView()
                .tabItem {
                    Label("频道", systemImage: "radio")
                }
            
            PodcastLearningView(podcast: .sample)
                .tabItem {
                    Label("学习", systemImage: "book")
                }
        }
    }
}

#Preview {
    ContentView()
}
