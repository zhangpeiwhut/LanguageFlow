//
//  ChannelListView.swift
//  LanguageFlow
//

import SwiftUI

struct FirstLevelView: View {
    @State private var channels: [Channel] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
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
                } else {
                    List(channels) { channel in
                        NavigationLink(destination: SecondLevelView(channel: channel)) {
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
            .navigationTitle("频道")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                loadChannels()
            }
        }
    }
    
    private func loadChannels() {
        guard channels.isEmpty else { return }
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
    FirstLevelView()
}

