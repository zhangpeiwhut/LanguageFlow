//
//  SecondLevelView.swift
//  LanguageFlow
//

import SwiftUI

struct SecondLevelView: View {
    let channel: Channel
    @State private var timestamps: [Int] = []
    @State private var selectedTimestamp: Int?
    @State private var podcasts: [PodcastSummary] = []
    @State private var cachedPodcasts: [Int: [PodcastSummary]] = [:]
    @State private var isLoadingDates = false
    @State private var isLoadingPodcasts = false
    @State private var errorMessage: String?
    @State private var areTranslationsHidden = true

    var body: some View {
        Group {
            if isLoadingDates {
                ProgressView()
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
                                ProgressView()
                            } else {
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
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(selectedTimestamp == timestamp ? .accentColor : .primary)
                            .padding(.vertical, 5)
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
            .padding(.vertical, 8)
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
                timestamps = Array(timestamps.prefix(30))
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
        if let cached = cachedPodcasts[timestamp] {
            podcasts = cached
            return
        }

        Task { @MainActor in
            isLoadingPodcasts = true
            do {
                podcasts = try await PodcastAPI.shared.getChannelPodcasts(
                    company: channel.company,
                    channel: channel.channel,
                    timestamp: timestamp
                )
                cachedPodcasts[timestamp] = podcasts
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

// MARK: - Podcast Card
struct PodcastCardView: View {
    let podcast: PodcastSummary
    let showTranslation: Bool
    let durationText: String
    let segmentText: String

    private var originalTitle: String {
        stripTrailingPeriod(podcast.title ?? podcast.titleTranslation ?? "无标题")
    }

    private var translatedTitle: String? {
        guard let translation = podcast.titleTranslation, !translation.isEmpty else { return nil }
        return stripTrailingPeriod(translation)
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
