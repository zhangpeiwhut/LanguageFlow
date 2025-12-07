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
    private let pageLimit: Int = 20
    @State private var isInitialLoading = false
    @State private var isPageLoading = false
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
                        pageControls
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
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
        await loadPage(page: 1)
    }

    func loadPage(page: Int) async {
        let targetPage = max(1, page)
        if targetPage == 1 && podcasts.isEmpty {
            isInitialLoading = true
        }
        isPageLoading = true
        errorMessage = nil

        do {
            let response = try await PodcastAPI.shared.getChannelPodcastsPaged(
                company: channel.company,
                channel: channel.channel,
                page: targetPage,
                limit: pageLimit
            )
            let newItems = response.podcasts
            await MainActor.run {
                podcasts = newItems
                currentPage = targetPage
                totalCount = response.total
                let computedPages = Int(ceil(Double(response.total) / Double(response.limit)))
                totalPages = max(1, response.totalPages ?? computedPages)
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isInitialLoading = false
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

    @ViewBuilder
    var pageControls: some View {
        if totalPages > 1 || isPageLoading {
            HStack(spacing: 12) {
                Button {
                    Task { await loadPage(page: max(1, currentPage - 1)) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                }
                .disabled(currentPage <= 1 || isPageLoading)

                Text("第 \(currentPage) 页 / 共 \(totalPages) 页")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await loadPage(page: min(totalPages, currentPage + 1)) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.bold())
                }
                .disabled(currentPage >= totalPages || isPageLoading)

                if isPageLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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
