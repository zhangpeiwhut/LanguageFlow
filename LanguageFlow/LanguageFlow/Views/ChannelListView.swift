//
//  ChannelListView.swift
//  LanguageFlow
//

import SwiftUI

struct ChannelListView: View {
    @State private var channels: [Channel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
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
                            loadChannels()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if channels.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "radio")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无频道")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(channels) { channel in
                        NavigationLink(destination: ChannelDatesView(channel: channel)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.channel)
                                    .font(.headline)
                                Text(channel.company)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .task {
                loadChannels()
            }
        }
    }
    
    private func loadChannels() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                channels = try await PodcastAPI.shared.getAllChannels()
            } catch {
                errorMessage = error.localizedDescription
                print("加载频道失败: \(error)")
            }
            
            isLoading = false
        }
    }
}

#Preview {
    ChannelListView()
}

