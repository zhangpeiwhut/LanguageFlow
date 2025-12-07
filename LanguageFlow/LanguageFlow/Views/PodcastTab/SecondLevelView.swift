//
//  SecondLevelView.swift
//  LanguageFlow
//

import SwiftUI

struct SecondLevelView: View {
    let channel: Channel
    @State private var podcasts: [PodcastSummary] = []
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var totalCount: Int = 0
    @State private var pageCache: [Int: [PodcastSummary]] = [:]
    private let pageLimit: Int = 10
    @State private var isInitialLoading = false
    @State private var errorMessage: String?
    @State private var areTranslationsHidden = true

    var body: some View {
        Group {
            if isInitialLoading {
                ProgressView()
            } else if let error = errorMessage, podcasts.isEmpty {
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
                        Task { await loadFirstPageIfNeeded() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                VStack(spacing: 10) {
                    if totalPages > 1 {
                        pageSelector
                            .padding(.horizontal, 16)
                    }
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(podcasts) { podcast in
                                NavigationLink {
                                    PodcastLearningView(podcastId: podcast.id)
                                } label: {
                                    PodcastCardView(
                                        podcast: podcast,
                                        showTranslation: !areTranslationsHidden,
                                        durationText: formatDurationMinutes(podcast.duration),
                                        segmentText: formatSegmentCount(podcast.segmentCount)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 32)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .navigationTitle(channel.channel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        areTranslationsHidden.toggle()
                    }
                } label: {
                    Image(systemName: areTranslationsHidden ? "lightbulb.slash" : "lightbulb")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            await loadFirstPageIfNeeded()
        }
    }
}

private extension SecondLevelView {
    func loadFirstPageIfNeeded() async {
        guard podcasts.isEmpty else { return }
        pageCache.removeAll()
        await loadPage(page: 1)
    }

    func loadPage(page: Int) async {
        let targetPage = max(1, page)
        if let cached = pageCache[targetPage] {
            podcasts = cached
            currentPage = targetPage
            errorMessage = nil
            isInitialLoading = false
            return
        }
        if targetPage == 1 && podcasts.isEmpty {
            isInitialLoading = true
        }
        errorMessage = nil

        do {
            let response = try await PodcastAPI.shared.getChannelPodcastsPaged(
                company: channel.company,
                channel: channel.channel,
                page: targetPage,
                limit: pageLimit
            )
            let newItems = response.podcasts
            podcasts = newItems
            currentPage = targetPage
            totalCount = response.total
            let computedPages = Int(ceil(Double(response.total) / Double(response.limit)))
            totalPages = max(1, response.totalPages ?? computedPages)
            errorMessage = nil
            pageCache[targetPage] = newItems
        } catch {
            errorMessage = error.localizedDescription
        }
        isInitialLoading = false
    }

    func formatDurationMinutes(_ duration: Int?) -> String {
        guard let duration else { return "0分钟" }
        let minutes = max(Int(round(Double(duration) / 60.0)), 1)
        return "\(minutes)分钟"
    }

    func formatSegmentCount(_ count: Int?) -> String {
        guard let count else { return "0句" }
        return "\(count)句"
    }

    var pageSelector: some View {
        let pages = Array(1...max(totalPages, 1))
        return VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pages, id: \.self) { page in
                        Button {
                            guard page != currentPage else { return }
                            Task { await loadPage(page: page) }
                        } label: {
                            Text("\(page)")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(currentPage == page ? .accentColor : .primary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    Capsule().fill(
                                        currentPage == page
                                        ? Color.accentColor.opacity(0.14)
                                        : Color(uiColor: .secondarySystemGroupedBackground)
                                    )
                                )
                                .overlay(
                                    Capsule().stroke(
                                        currentPage == page ? Color.accentColor : Color.gray.opacity(0.25),
                                        lineWidth: 1
                                    )
                                )
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
            }
        }
    }
}

// MARK: - Podcast Card
struct PodcastCardView: View {
    let podcast: PodcastSummary
    let showTranslation: Bool
    let durationText: String
    let segmentText: String

    private var originalTitle: String {
        let base = (podcast.title ?? podcast.titleTranslation ?? "无标题").removingTrailingDateSuffix()
        return stripTrailingPeriod(base)
    }

    private var translatedTitle: String? {
        guard let translation = podcast.titleTranslation, !translation.isEmpty else { return nil }
        let cleaned = translation.removingTrailingDateSuffix()
        return stripTrailingPeriod(cleaned)
    }

    private func stripTrailingPeriod(_ text: String) -> String {
        var result = text
        while let last = result.last, last == "." || last == "。" {
            result.removeLast()
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(originalTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let translatedTitle {
                    Text(translatedTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .blur(radius: showTranslation ? 0 : 5)
                        .animation(.easeInOut(duration: 0.2), value: showTranslation)
                }
            }

            Text("\(durationText) • \(segmentText)")
                .font(.caption2)
                .foregroundColor(.secondary)
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
    }
}
