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
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPageLoading = false
    @State private var pageLoadError: String?
    @State private var areTranslationsHidden = true
    @State private var navigateToPodcastId: String?
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if errorMessage != nil {
                ErrorView {
                    Task { await loadPage(page: currentPage) }
                }
            } else {
                VStack(spacing: 10) {
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
                                    LazyVStack(spacing: 14) {
                                        ForEach(podcasts) { podcast in
                                            PodcastCardView(
                                                podcast: podcast,
                                                showTranslation: !areTranslationsHidden,
                                                durationText: formatDurationMinutes(podcast.duration),
                                                segmentText: formatSegmentCount(podcast.segmentCount),
                                                onTap: {
                                                    handlePodcastTap(podcast)
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, (!authManager.isVIP) ? 140 : 40)
                                }
                                .ignoresSafeArea(.container, edges: .bottom)

                                if !authManager.isVIP {
                                    subscriptionBanner
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
    func handlePodcastTap(_ podcast: PodcastSummary) {
        if podcast.isFree || authManager.isVIP {
            navigateToPodcastId = podcast.id
        }
    }

    var subscriptionBanner: some View {
        NavigationLink(destination: SubscriptionView()) {
            HStack(spacing: 12) {
                Image("king")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                Text("解锁 VIP 畅听无限")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .buttonStyle(.plain)
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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(currentPage == page ? .white : .primary)
                            .frame(minWidth: 36, minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(currentPage == page ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .shadow(color: currentPage == page ? Color.accentColor.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                    }
                    .disabled(page == currentPage)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Podcast Card
struct PodcastCardView: View {
    let podcast: PodcastSummary
    let showTranslation: Bool
    let durationText: String
    let segmentText: String
    let onTap: () -> Void

    @State private var shakeTrigger = 0
    @Environment(AuthManager.self) private var authManager

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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
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

                    Spacer()

                    if !podcast.isFree && !authManager.isVIP {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .keyframeAnimator(
                                initialValue: ShakeValues(),
                                trigger: shakeTrigger,
                                content: { view, values in
                                    view
                                        .rotationEffect(values.angle, anchor: .top)
                                }, keyframes: { _ in
                                    KeyframeTrack(\.angle) {
                                        LinearKeyframe(.zero, duration: 0)
                                        LinearKeyframe(.degrees(15), duration: 0.1)
                                        LinearKeyframe(.degrees(-15), duration: 0.2)
                                        LinearKeyframe(.zero, duration: 0.1)
                                    }
                                }
                            )
                    }
                }

                HStack(spacing: 8) {
                    Text("\(durationText) • \(segmentText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if podcast.isFree {
                        Text("免费试学")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.green.opacity(0.15))
                            )
                    }
                }
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
            handleTap()
        }
    }
    
    private func handleTap() {
        if podcast.isFree || authManager.isVIP {
            onTap()
        } else {
            shakeTrigger += 1
        }
    }
}

// MARK: - Shake Animation Values
struct ShakeValues {
    var angle: Angle = .zero
}
