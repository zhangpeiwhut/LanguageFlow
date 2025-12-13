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
    @State private var shakingPodcastAmounts: [String: CGFloat] = [:]
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
                                                shakeAmount: shakingPodcastAmounts[podcast.id] ?? 0
                                            )
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                handlePodcastTap(podcast)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, (!authManager.isVIP) ? 100 : 16)
                                }

                                // 底部订阅横幅（非VIP用户常驻显示）
                                if !authManager.isVIP {
                                    subscriptionBanner
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
            // 付费内容且非VIP：显示提示并摇晃
            shakePodcast(podcast.id)
            showToast("订阅 Pro 解锁完整内容")
            withAnimation(.easeInOut(duration: 0.3)) {
                showSubscriptionBanner = true
            }
        }
    }
    
    func shakePodcast(_ podcastId: String) {
        withAnimation(.linear(duration: 0.5).repeatCount(6, autoreverses: false)) {
            shakingPodcastAmounts[podcastId] = 6.0
        }
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6秒
            withAnimation {
                shakingPodcastAmounts.removeValue(forKey: podcastId)
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
            HStack(spacing: 16) {
                // 图标容器
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "crown.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("解锁所有播客内容")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("订阅 Pro 畅听无限")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                Spacer()
                
                // 箭头图标
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // 渐变背景
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.4, blue: 1.0),
                            Color(red: 0.4, green: 0.2, blue: 0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // 装饰性光效
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.clear,
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color(red: 0.2, green: 0.4, blue: 1.0).opacity(0.4), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
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
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(
                    .ultraThinMaterial
                )
                .overlay(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.9),
                                    Color.accentColor.opacity(0.7)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.accentColor.opacity(0.3), radius: 12, x: 0, y: 4)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Podcast Card
struct PodcastCardView: View {
    let podcast: PodcastSummary
    let showTranslation: Bool
    let durationText: String
    let segmentText: String
    let shakeAmount: CGFloat
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
                            .modifier(ShakeEffect(animatableData: shakeAmount))
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

// MARK: - Shake Effect
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(animatableData * .pi * 2) * 8
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
