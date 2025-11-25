//
//  FavoritePodcastsView.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 11/24/25.
//

import SwiftUI
import SwiftData

// MARK: - 整篇收藏
struct FavoritePodcastsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoritePodcast.createdAt, order: .reverse) private var favoritePodcastsData: [FavoritePodcast]
    @State private var favoritePodcasts: [FavoritePodcast] = []
    @State private var presentingPodcast: FavoritePodcast?
    
    var body: some View {
        NavigationStack {
            Group {
                if favoritePodcasts.isEmpty {
                    emptyState(
                        systemImage: "text.book.closed",
                        title: "暂无整篇收藏",
                        message: "收藏整篇后会显示在这里"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(favoritePodcasts, id: \.id) { podcast in
                                FavoritePodcastCard(
                                    title: podcast.title ?? "未命名节目",
                                    subtitle: podcast.subtitle,
                                    durationText: durationText(for: podcast),
                                    segmentText: segmentText(for: podcast),
                                    onOpen: {
                                        presentingPodcast = podcast
                                    },
                                    onUnfavorite: {
                                        Task {
                                            do {
                                                try await FavoriteManager.shared.unfavoritePodcast(podcast.id, context: modelContext)
                                                await MainActor.run { syncFavorites() }
                                            } catch {
                                                print("取消收藏失败: \(error)")
                                            }
                                        }
                                    }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("整篇收藏")
            .onAppear(perform: syncFavorites)
            .onChange(of: favoritePodcastsData.count) { _, _ in syncFavorites() }
            .fullScreenCover(item: $presentingPodcast) { podcast in
                PodcastLearningView(podcastId: podcast.id)
            }
        }
    }
}

private extension FavoritePodcastsView {
    func syncFavorites() {
        favoritePodcasts = favoritePodcastsData
    }

    func emptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func durationText(for podcast: FavoritePodcast) -> String {
        let totalSeconds = podcast.duration ?? 0
        guard totalSeconds > 0 else { return "未知时长" }
        let minutes = (totalSeconds + 59) / 60
        return "\(minutes)分钟"
    }

    func segmentText(for podcast: FavoritePodcast) -> String {
        return "\(podcast.segmentCount)句"
    }
}

private struct FavoritePodcastCard: View {
    let title: String
    let subtitle: String?
    let durationText: String
    let segmentText: String
    let onOpen: () -> Void
    let onUnfavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Text("\(durationText) • \(segmentText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onUnfavorite) {
                    Image(systemName: "heart.slash.fill")
                        .font(.caption)
                        .foregroundColor(.pink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}
