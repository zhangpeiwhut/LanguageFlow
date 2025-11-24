//
//  FavoritesView.swift
//  LanguageFlow
//

import SwiftUI
import SwiftData
import AVFoundation
import Observation
import Combine

// MARK: - 整篇收藏
struct FavoritePodcastsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoritePodcast.createdAt, order: .reverse) private var favoritePodcastsData: [FavoritePodcast]
    @State private var favoritePodcasts: [FavoritePodcast] = []
    @State private var presentingPodcast: FavoritePodcast?
    
    var body: some View {
        NavigationStack {
            Group {
                if favoritePodcasts.isEmpty {
                    emptyState(
                        systemImage: "text.book.closed",
                        title: "暂无整篇收藏",
                        message: "收藏整篇后会显示在这里"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(favoritePodcasts, id: \.id) { podcast in
                                FavoritePodcastCard(
                                    title: podcast.title ?? "未命名节目",
                                    subtitle: podcast.subtitle,
                                    durationText: durationText(for: podcast),
                                    segmentText: segmentText(for: podcast),
                                    onOpen: {
                                        presentingPodcast = podcast
                                    },
                                    onUnfavorite: {
                                        Task {
                                            do {
                                                try await FavoriteManager.shared.unfavoritePodcast(podcast.id, context: modelContext)
                                                await MainActor.run { syncFavorites() }
                                            } catch {
                                                print("取消收藏失败: \(error)")
                                            }
                                        }
                                    }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("整篇收藏")
            .onAppear(perform: syncFavorites)
            .onChange(of: favoritePodcastsData.count) { _, _ in syncFavorites() }
            .fullScreenCover(item: $presentingPodcast) { podcast in
                PodcastLearningView(podcastId: podcast.id)
            }
        }
    }
}

private extension FavoritePodcastsView {
    func syncFavorites() {
        favoritePodcasts = favoritePodcastsData
    }
    
    func emptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    func durationText(for podcast: FavoritePodcast) -> String {
        let totalSeconds = podcast.duration ?? 0
        guard totalSeconds > 0 else { return "未知时长" }
        let minutes = (totalSeconds + 59) / 60
        return "\(minutes)分钟"
    }
    
    func segmentText(for podcast: FavoritePodcast) -> String {
        return "\(podcast.segmentCount)句"
    }
}

// MARK: - 单句收藏
struct FavoriteSegmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteSegment.createdAt, order: .reverse) private var favoriteSegmentsData: [FavoriteSegment]
    @State private var favoriteSegments: [FavoritePodcastSegment] = []
    @State private var errorMessage: String?
    @State private var segmentPlayer: SegmentInlinePlayer?
    @State private var segmentPlaybackRates: [String: Double] = [:]
    @State private var segmentTranslationVisibility: [String: Bool] = [:]
    
    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("加载失败")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            syncFavorites()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if favoriteSegments.isEmpty {
                    emptyState(
                        systemImage: "text.quote",
                        title: "暂无单句收藏",
                        message: "收藏的单句将显示在这里"
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(favoriteSegments.enumerated()), id: \.element.id) { index, segment in
                                FavoriteSegmentCardView(
                                    segment: segment,
                                    segmentNumber: index + 1,
                                    totalSegments: favoriteSegments.count,
                                    currentPlayer: segmentPlayer,
                                    isPlaying: segmentPlayer?.segmentId == segment.id && segmentPlayer?.isPlaying == true,
                                    playbackRate: segmentPlaybackRates[segment.id] ?? 1.0,
                                    isTranslationVisible: segmentTranslationVisibility[segment.id] ?? true,
                                    onPlay: {
                                        startPlayback(for: segment)
                                    },
                                    onUnfavorite: {
                                        Task {
                                            do {
                                                try await FavoriteManager.shared.unfavoriteSegment(segment.id, context: modelContext)
                                                await MainActor.run { syncFavorites() }
                                            } catch {
                                                print("取消收藏失败: \(error)")
                                            }
                                        }
                                    },
                                    onRateChange: { rate in
                                        segmentPlaybackRates[segment.id] = rate
                                        if segmentPlayer?.segmentId == segment.id {
                                            segmentPlayer?.playbackRate = rate
                                        }
                                    },
                                    onToggleTranslation: {
                                        let currentValue = segmentTranslationVisibility[segment.id] ?? true
                                        segmentTranslationVisibility[segment.id] = !currentValue
                                    }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
            .navigationTitle("单句收藏")
            .onAppear(perform: syncFavorites)
            .onChange(of: favoriteSegmentsData.count) { _, _ in syncFavorites() }
            .onDisappear {
                segmentPlayer?.stop()
            }
        }
    }
}

private extension FavoriteSegmentsView {
    func emptyState(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @MainActor
    func syncFavorites() {
        errorMessage = nil
        favoriteSegments = favoriteSegmentsData.map { $0.toFavoritePodcastSegment() }
        let ids = Set(favoriteSegments.map(\.id))
        segmentPlaybackRates = segmentPlaybackRates.filter { ids.contains($0.key) }
        segmentTranslationVisibility = segmentTranslationVisibility.filter { ids.contains($0.key) }
        for id in ids {
            if segmentPlaybackRates[id] == nil { segmentPlaybackRates[id] = 1.0 }
            if segmentTranslationVisibility[id] == nil { segmentTranslationVisibility[id] = true }
        }
        
        if let currentId = segmentPlayer?.segmentId, !ids.contains(currentId) {
            segmentPlayer?.stop()
            segmentPlayer = nil
        }
    }
    
    func startPlayback(for segment: FavoritePodcastSegment) {
        Task { @MainActor in
            if let player = segmentPlayer, player.segmentId == segment.id {
                player.togglePlayback()
                return
            }
            segmentPlayer?.stop()
            let player = SegmentInlinePlayer(segment: segment)
            segmentPlayer = player
            let rate = segmentPlaybackRates[segment.id] ?? 1.0
            let didPrepare = await player.prepareAndPlay(playbackRate: rate)
            if !didPrepare {
                errorMessage = "音频不可用，请稍后重试"
                segmentPlayer = nil
            }
        }
    }
}

// MARK: - Favorite Segment Card
struct FavoriteSegmentCardView: View {
    let segment: FavoritePodcastSegment
    let segmentNumber: Int
    let totalSegments: Int
    let currentPlayer: SegmentInlinePlayer?
    let isPlaying: Bool
    let playbackRate: Double
    let isTranslationVisible: Bool
    let onPlay: () -> Void
    let onUnfavorite: () -> Void
    let onRateChange: (Double) -> Void
    let onToggleTranslation: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            numberTag()

            Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if let translation = segment.translation {
                Text(translation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blur(radius: !isTranslationVisible ? 5 : 0)
                    .animation(.easeInOut(duration: 0.2), value: !isTranslationVisible)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onToggleTranslation()
                    }
            }
            
            FavoriteSegmentControls(
                playbackRate: playbackRate,
                onUnfavorite: onUnfavorite,
                onRateChange: onRateChange
            )
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isPlaying ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isPlaying ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay()
        }
    }
    
    @ViewBuilder
    private func numberTag() -> some View {
        Text("\(segmentNumber)/\(totalSegments)")
            .font(.caption.bold())
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemFill))
            )
    }
}

// MARK: - Favorite Podcast Card
private struct FavoritePodcastCard: View {
    let title: String
    let subtitle: String?
    let durationText: String
    let segmentText: String
    let onOpen: () -> Void
    let onUnfavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 10) {
                Text("\(durationText) • \(segmentText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onUnfavorite) {
                    Image(systemName: "heart.slash.fill")
                        .font(.caption)
                        .foregroundColor(.pink)
                }
                .buttonStyle(.plain)
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
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
    }
}

// MARK: - Favorite Segment Controls
private struct FavoriteSegmentControls: View {
    let playbackRate: Double
    let onUnfavorite: () -> Void
    let onRateChange: (Double) -> Void

    private let rateOptions: [Double] = [0.75, 1.0, 1.25]
    
    private func nextRate() -> Double {
        guard let currentIndex = rateOptions.firstIndex(of: playbackRate) else {
            return rateOptions[0]
        }
        let nextIndex = (currentIndex + 1) % rateOptions.count
        return rateOptions[nextIndex]
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            Button {
                onRateChange(nextRate())
            } label: {
                Text("\(playbackRate, specifier: "%.2fx")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("倍速 \(playbackRate, specifier: "%.2fx")")
            
            Button(action: onUnfavorite) {
                Image(systemName: "heart.fill")
                    .font(.body)
                    .foregroundColor(.pink)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Inline Segment Player
@Observable
final class SegmentInlinePlayer {
    let segment: FavoritePodcastSegment
    let segmentId: String
    var isPlaying = false
    var playbackRate: Double = 1.0 {
        didSet {
            updatePlayerRate()
        }
    }
    
    @ObservationIgnored private var audioPlayer: AVPlayer?
    @ObservationIgnored private var playbackFinishedObserver: AnyCancellable?
    @ObservationIgnored private var timeObserver: Any?
    
    init(segment: FavoritePodcastSegment) {
        self.segment = segment
        self.segmentId = segment.id
    }
    
    deinit {
        cleanup()
    }
    
    /// 准备播放：确保整篇音频已下载，然后按时间片段播放
    @MainActor
    func prepareAndPlay(playbackRate: Double) async -> Bool {
        self.playbackRate = playbackRate
        
        do {
            let localAudioURL = try await FavoriteManager.shared.ensureLocalAudio(for: segment)
            setupLocalPlayer(with: localAudioURL)
            play()
            return true
        } catch {
            print("收藏片段播放失败: \(error)")
            cleanup()
            return false
        }
    }
    
    func play() {
        guard let player = audioPlayer else { return }
        let currentSeconds = player.currentTime().seconds
        if currentSeconds < segment.startTime || currentSeconds >= segment.endTime {
            seekToSegmentStart()
        }
        player.rate = Float(playbackRate)
        player.play()
        isPlaying = true
    }
    
    private func updatePlayerRate() {
        guard let player = audioPlayer else { return }
        if isPlaying {
            player.rate = Float(playbackRate)
        }
    }
    
    func stop() {
        audioPlayer?.pause()
        isPlaying = false
    }
    
    func togglePlayback() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }
    
    private func seekToSegmentStart() {
        guard let player = audioPlayer else { return }
        let startTime = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        player.seek(to: startTime) { [weak self] _ in
            self?.play()
        }
    }
    
    private func setupLocalPlayer(with url: URL) {
        cleanup()
        audioPlayer = AVPlayer(url: url)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let currentSeconds = time.seconds
            if currentSeconds >= self.segment.endTime {
                self.audioPlayer?.pause()
                self.isPlaying = false
                if let observer = self.timeObserver {
                    self.audioPlayer?.removeTimeObserver(observer)
                    self.timeObserver = nil
                }
            }
        }
        
        playbackFinishedObserver = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                self?.stop()
                self?.seekToSegmentStart()
            }
    }
    
    private func cleanup() {
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        audioPlayer?.pause()
        audioPlayer = nil
        isPlaying = false
    }
}
