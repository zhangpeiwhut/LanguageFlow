//
//  FavoritePodcastsView.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 11/24/25.
//

import SwiftUI
import SwiftData

// MARK: - 整篇收藏
struct FavoritePodcastsView<EmptyView: View>: View {
    @Binding var navigationPath: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoritePodcast.createdAt, order: .reverse) private var favoritePodcasts: [FavoritePodcast]
    @ViewBuilder var emptyView: EmptyView

    var body: some View {
        Group {
            if favoritePodcasts.isEmpty {
                emptyView
            } else {
                contentList
            }
        }
    }
}

private extension FavoritePodcastsView {
    var contentList: some View {
        LazyVStack(spacing: 14) {
            ForEach(favoritePodcasts, id: \.id) { podcast in
                FavoritePodcastCard(
                    title: (podcast.title ?? "未命名节目").removingTrailingDateSuffix(),
                    titleTranslation: podcast.titleTranslation?.removingTrailingDateSuffix(),
                    durationText: durationText(for: podcast),
                    segmentText: segmentText(for: podcast),
                    onOpen: {
                        navigationPath.append(podcast.id)
                    },
                    onUnfavorite: {
                        Task {
                            do {
                                try await FavoriteManager.shared.unfavoritePodcast(podcast.id, context: modelContext)
                            } catch {
                                print("取消收藏失败: \(error)")
                            }
                        }
                    }
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 32)
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
    let titleTranslation: String?
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
            if let titleTranslation, !titleTranslation.isEmpty {
                Text(titleTranslation)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                Text("\(durationText) • \(segmentText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onUnfavorite) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundColor(.red)
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
