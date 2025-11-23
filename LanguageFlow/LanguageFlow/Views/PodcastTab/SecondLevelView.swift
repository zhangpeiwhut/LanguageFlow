//
//  SecondLevelView.swift
//  LanguageFlow
//

import SwiftUI
import SwiftfulLoadingIndicators

struct SecondLevelView: View {
    let channel: Channel
    @State private var timestamps: [Int] = []
    @State private var selectedTimestamp: Int?
    @State private var podcasts: [PodcastSummary] = []
    @State private var presentingPodcast: PodcastSummary?
    @State private var isLoadingDates = false
    @State private var isLoadingPodcasts = false
    @State private var errorMessage: String?
    @State private var areTranslationsHidden = true

    var body: some View {
        Group {
            if isLoadingDates {
                LoadingIndicator(animation: .fiveLines)
            } else if let error = errorMessage, timestamps.isEmpty {
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
                        loadDates()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    dateSelector
                    Divider()
                    ScrollView {
                        VStack(spacing: 20) {
                            if isLoadingPodcasts {
                                LoadingIndicator(animation: .fiveLines)
                                    .frame(maxWidth: .infinity)
                            } else {
                                WaterfallGrid(items: podcasts, spacing: 14) { podcast in
                                    Button {
                                        presentingPodcast = podcast
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
                                .animation(.easeInOut(duration: 0.3), value: areTranslationsHidden)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
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
            }
        }
        .task {
            loadDates()
        }
        .onChange(of: selectedTimestamp) { _, newValue in
            guard let newValue else { return }
            loadPodcasts(for: newValue)
        }
        .fullScreenCover(item: $presentingPodcast) { podcast in
            PodcastLearningView(podcastId: podcast.id)
        }
    }

    private var dateSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(timestamps, id: \.self) { timestamp in
                    let label = formatDateLabel(timestamp)
                    Button {
                        selectedTimestamp = timestamp
                    } label: {
                        Text(label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(selectedTimestamp == timestamp ? .accentColor : .primary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .frame(minWidth: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedTimestamp == timestamp ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedTimestamp == timestamp ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private extension SecondLevelView {
    func loadDates() {
        guard timestamps.isEmpty else { return }
        Task { @MainActor in
            isLoadingDates = true
            errorMessage = nil
            do {
                timestamps = try await PodcastAPI.shared.getChannelDates(
                    company: channel.company,
                    channel: channel.channel
                )
                timestamps = Array(timestamps.prefix(7))
                if let firstTimestamp = timestamps.first {
                    selectedTimestamp = firstTimestamp
                }
            } catch {
                errorMessage = error.localizedDescription
                print("加载日期失败: \(error)")
            }
            isLoadingDates = false
        }
    }

    func loadPodcasts(for timestamp: Int) {
        Task { @MainActor in
            isLoadingPodcasts = true
            do {
                podcasts = try await PodcastAPI.shared.getChannelPodcasts(
                    company: channel.company,
                    channel: channel.channel,
                    timestamp: timestamp
                )
            } catch {
                print("加载podcasts失败: \(error)")
                podcasts = []
            }

            isLoadingPodcasts = false
        }
    }

    func formatDateLabel(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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
}

// MARK: - Waterfall Grid
struct WaterfallGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let items: Data
    private let content: (Data.Element) -> Content
    private let spacing: CGFloat

    init(items: Data, spacing: CGFloat = 12, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.content = content
        self.spacing = spacing
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            LazyVStack(spacing: spacing) {
                ForEach(leftColumn) { item in
                    content(item)
                }
            }
            LazyVStack(spacing: spacing) {
                ForEach(rightColumn) { item in
                    content(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var leftColumn: [Data.Element] {
        items.enumerated().compactMap { index, element in
            index.isMultiple(of: 2) ? element : nil
        }
    }

    private var rightColumn: [Data.Element] {
        items.enumerated().compactMap { index, element in
            index.isMultiple(of: 2) ? nil : element
        }
    }
}

// MARK: - Podcast Card
struct PodcastCardView: View {
    let podcast: PodcastSummary
    let showTranslation: Bool
    let durationText: String
    let segmentText: String

    private var displayTitle: String {
        if showTranslation {
            return stripTrailingPeriod(podcast.titleTranslation ?? podcast.title ?? "无标题")
        }
        return stripTrailingPeriod(podcast.title ?? podcast.titleTranslation ?? "无标题")
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
            Text(displayTitle)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

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
