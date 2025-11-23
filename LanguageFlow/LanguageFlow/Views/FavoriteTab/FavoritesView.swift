//
//  FavoritesView.swift
//  LanguageFlow
//

import SwiftUI

struct FavoritesView: View {
    @State private var favoritePodcasts: [PodcastSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("加载失败")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            loadFavorites()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if favoritePodcasts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无收藏")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("收藏的Podcast将显示在这里")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(favoritePodcasts) { podcast in
                        NavigationLink(destination: PodcastLearningView(podcastId: podcast.id)) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let title = podcast.title {
                                    Text(title)
                                        .font(.headline)
                                        .lineLimit(2)
                                } else {
                                    Text("无标题")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.large)
            .task {
                loadFavorites()
            }
            .refreshable {
                loadFavorites()
            }
        }
    }
    
    private func loadFavorites() {
        Task {
            isLoading = true
            errorMessage = nil
            
            // TODO: 实现获取收藏列表的API
            // 目前先返回空列表
            favoritePodcasts = []
            
            isLoading = false
        }
    }
}

#Preview {
    FavoritesView()
}

