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
    @State private var isLoadingDates = false
    @State private var isLoadingPodcasts = false
    @State private var errorMessage: String?

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
            } else if timestamps.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无内容")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // 日期选择器
                        Menu {
                            ForEach(timestamps, id: \.self) { timestamp in
                                Button(action: {
                                    selectedTimestamp = timestamp
                                }) {
                                    HStack {
                                        Text(formatDate(timestamp))
                                        if selectedTimestamp == timestamp {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .foregroundColor(.blue)

                                if let timestamp = selectedTimestamp {
                                    Text(formatDate(timestamp))
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                } else {
                                    Text("选择日期")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                        }

                        // 播客网格
                        if isLoadingPodcasts {
                            LoadingIndicator(animation: .fiveLines)
                                .frame(height: 200)
                        } else if podcasts.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "waveform")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("暂无Podcast")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 200)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(podcasts) { podcast in
                                    NavigationLink(destination: PodcastLearningView(podcastId: podcast.id)) {
                                        PodcastCardView(podcast: podcast)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .navigationTitle(channel.channel)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadDates()
        }
        .onChange(of: selectedTimestamp) { oldValue, newValue in
            if let timestamp = newValue {
                loadPodcasts(for: timestamp)
            }
        }
    }

    private func loadDates() {
        guard timestamps.isEmpty else { return }
        Task {
            isLoadingDates = true
            errorMessage = nil

            do {
                timestamps = try await PodcastAPI.shared.getChannelDates(
                    company: channel.company,
                    channel: channel.channel
                )

                // 默认选择最新日期（第一个）
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

    private func loadPodcasts(for timestamp: Int) {
        Task {
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

    private func formatDate(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Podcast Card
struct PodcastCardView: View {
    let podcast: PodcastSummary

    var body: some View {
        VStack(spacing: 12) {
            // 顶部图标
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 60, height: 60)

                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

            // 标题
            if let title = podcast.title {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("无标题")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}
