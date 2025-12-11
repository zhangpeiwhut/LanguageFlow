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
    @State private var showSubscriptionBanner = false
    @State private var toastMessage: String?
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
                                                segmentText: formatSegmentCount(podcast.segmentCount)
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                handlePodcastTap(podcast)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, showSubscriptionBanner ? 80 : 16)
                                }

                                // 底部订阅横幅
                                if showSubscriptionBanner {
                                    subscriptionBanner
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 32)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .navigationTitle(channel.channel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $navigateToPodcastId) { podcastId in
            PodcastLearningView(podcastId: podcastId)
        }
        .overlay(alignment: .top) {
            // Toast 提示
            if let message = toastMessage {
                ToastView(message: message)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
            }
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
        // 免费内容或VIP用户：直接导航
        if podcast.isFree || authManager.isVIP {
            navigateToPodcastId = podcast.id
        } else {
            // 付费内容且非VIP：显示提示
            showToast("订阅 Pro 解锁完整内容")
            withAnimation(.easeInOut(duration: 0.3)) {
                showSubscriptionBanner = true
            }
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3秒
            withAnimation {
                toastMessage = nil
            }
        }
    }

    var subscriptionBanner: some View {
        NavigationLink(destination: SubscriptionView()) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("解锁所有播客内容")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("订阅 Pro 畅听无限")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
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

            // 检查是否还在当前页面，防止竞态条件
            guard currentPage == targetPage else {
                // 用户已经切换到其他页面了，只缓存数据，不更新UI
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
            // 同样检查是否还在当前页面
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

// MARK: - Toast View
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
            )
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Podcast Card
struct PodcastCardView: View {
    let podcast: PodcastSummary
    let showTranslation: Bool
    let durationText: String
    let segmentText: String
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

                    // 锁图标（非VIP用户看到付费内容）
                    if !podcast.isFree && !authManager.isVIP {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(durationText) • \(segmentText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // 免费试听标签
                    if podcast.isFree {
                        Text("免费试听")
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
    }
}
