//
//  ChannelDatesView.swift
//  LanguageFlow
//

import SwiftUI
import SwiftfulLoadingIndicators

struct SecondLevelView: View {
    let channel: Channel
    @State private var timestamps: [Int] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                LoadingIndicator(animation: .fiveLines)
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
                    Text("暂无日期")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                List(timestamps, id: \.self) { timestamp in
                    NavigationLink(destination: ThirdLevelView(
                        channel: channel,
                        timestamp: timestamp
                    )) {
                        HStack {
                            Text(formatTimestamp(timestamp))
                                .font(.headline)
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(channel.channel)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadDates()
        }
    }
    
    private func loadDates() {
        guard timestamps.isEmpty else { return }
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                timestamps = try await PodcastAPI.shared.getChannelDates(
                    company: channel.company,
                    channel: channel.channel
                )
            } catch {
                errorMessage = error.localizedDescription
                print("加载日期失败: \(error)")
            }
            
            isLoading = false
        }
    }
    
    private func formatTimestamp(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
