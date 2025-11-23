//
//  ChannelPodcastsView.swift
//  LanguageFlow
//

import SwiftUI

struct ChannelPodcastsView: View {
    let channel: Channel
    let timestamp: Int
    @State private var podcasts: [PodcastSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
            } else if let error = errorMessage {
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
                        loadPodcasts()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if podcasts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无Podcast")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                List(podcasts) { podcast in
                    NavigationLink(destination: PodcastLearningView(podcastId: podcast.id)) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let title = podcast.title {
                                Text(title)
                                    .font(.headline)
                                    .lineLimit(2)
                            } else {
                                Text("无标题")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(formatDate(timestamp))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadPodcasts()
        }
    }
    
    private func loadPodcasts() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                podcasts = try await PodcastAPI.shared.getChannelPodcasts(
                    company: channel.company,
                    channel: channel.channel,
                    timestamp: timestamp
                )
            } catch {
                errorMessage = error.localizedDescription
                print("加载podcasts失败: \(error)")
            }
            
            isLoading = false
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

