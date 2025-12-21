//
//  SecondLevelView.swift
//  LanguageFlow
//

import SwiftUI
import SwiftData

struct SecondLevelView: View {
    let channel: Channel
    @State private var podcasts: [PodcastSummary] = []
    @State private var currentPage: Int = 1
    @State private var totalPages: Int = 1
    @State private var totalCount: Int = 0
    @State private var pageCache: [Int: [PodcastSummary]] = [:]
    private let pageLimit: Int = 10
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPageLoading = false
    @State private var pageLoadError: String?
    @State private var areTranslationsHidden = true
    @State private var navigateToPodcastId: String?
    @Query(sort: \CompletedPodcast.completedAt, order: .reverse) private var completedPodcasts: [CompletedPodcast]
    @Environment(AuthManager.self) private var authManager
    @Environment(ToastManager.self) private var toastManager

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if errorMessage != nil {
                ErrorView {
                    Task { await loadPage(page: currentPage) }
                }
            } else {
                VStack(spacing: 12) {
                    if totalPages > 1 {
                        pageSelector
                            .padding(.horizontal, 16)
                    }

                    Group {
                        if isPageLoading {
                            LoadingView()
                        } else if pageLoadError != nil  {
                            ErrorView {
                                Task { await loadPage(page: currentPage) }
                            }
                        } else {
                            ZStack(alignment: .bottom) {
                                ScrollView {
                                    LazyVStack(spacing: 12) {
                                        ForEach(podcasts) { podcast in
                                            PodcastCardView(
                                                podcast: podcast,
                                                showTranslation: !areTranslationsHidden,
                                                durationText: formatDurationMinutes(podcast.duration),
                                                segmentText: formatSegmentCount(podcast.segmentCount),
                                                onTap: {
                                                    handlePodcastTap(podcast)
                                                },
                                                isCompleted: completedIDs.contains(podcast.id)
                                            )
                                        }
                                    }
                                    .padding(.top, totalPages == 1 ? 6 : 0)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, (!authManager.isVIP) ? 180 : 40)
                                }
                                .ignoresSafeArea(.container, edges: .bottom)

                                if !authManager.isVIP {
                                    VIPSubscriptionBanner()
                                }
                            }
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .navigationTitle(channel.channel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $navigateToPodcastId) { podcastId in
            PodcastLearningView(podcastId: podcastId)
        }
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
    var completedIDs: Set<String> {
        Set(completedPodcasts.map(\.podcastId))
    }

    func handlePodcastTap(_ podcast: PodcastSummary) {
        if podcast.isFree || authManager.isVIP {
            navigateToPodcastId = podcast.id
        } else {
            toastManager.show(
                "该内容为会员专享",
                icon: "evil",
                iconSource: .asset,
                iconSize: CGSize(width: 34, height: 34),
                duration: 1.2
            )
        }
    }

    func loadFirstPageIfNeeded() async {
        guard podcasts.isEmpty else { return }
        pageCache.removeAll()
        await loadPage(page: 1)
    }

    func loadPage(page: Int) async {
        let targetPage = max(1, page)

        let isFirstLoad = targetPage == 1 && podcasts.isEmpty

        if let cached = pageCache[targetPage] {
            if !isFirstLoad {
                currentPage = targetPage
            }
            podcasts = cached
            currentPage = targetPage
            errorMessage = nil
            pageLoadError = nil
            isLoading = false
            isPageLoading = false
            return
        }

        if isFirstLoad {
            isLoading = true
            errorMessage = nil
        } else {
            currentPage = targetPage
            isPageLoading = true
            pageLoadError = nil
        }

        do {
            let response = try await PodcastAPI.shared.getChannelPodcastsPaged(
                company: channel.company,
                channel: channel.channel,
                page: targetPage,
                limit: pageLimit
            )

            guard currentPage == targetPage else {
                pageCache[targetPage] = response.podcasts
                return
            }

            let newItems = response.podcasts
            podcasts = newItems
            totalCount = response.total
            let computedPages = Int(ceil(Double(response.total) / Double(response.limit)))
            totalPages = max(1, response.totalPages ?? computedPages)
            pageCache[targetPage] = newItems

            if isFirstLoad {
                errorMessage = nil
            } else {
                pageLoadError = nil
            }
        } catch {
            guard currentPage == targetPage else {
                return
            }

            if isFirstLoad {
                errorMessage = error.localizedDescription
            } else {
                pageLoadError = error.localizedDescription
            }
        }

        if isFirstLoad {
            isLoading = false
        } else {
            isPageLoading = false
        }
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
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(pages, id: \.self) { page in
                    Button {
                        guard page != currentPage else { return }
                        Task { await loadPage(page: page) }
                    } label: {
                        Text("\(page)")
                            .font(.system(size: 16, weight: currentPage == page ? .semibold : .medium))
                            .foregroundColor(currentPage == page ? .primary : .secondary)
                            .frame(minWidth: 36, minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(currentPage == page ? Color(uiColor: .systemBackground) : Color(uiColor: .secondarySystemGroupedBackground))
                            )
                    }
                    .disabled(page == currentPage)
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
    }
}
