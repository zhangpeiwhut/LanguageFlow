//
//  FavoriteSegmentsView.swift
//  LanguageFlow
//

import SwiftUI
import SwiftData
import AVFoundation
import Observation
import Combine

// MARK: - 单句收藏
struct FavoriteSegmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoriteSegment.createdAt, order: .reverse) private var favoriteSegmentsData: [FavoriteSegment]
    @State private var favoriteSegments: [FavoritePodcastSegment] = []
    @State private var segmentPlayer: SegmentInlinePlayer?
    @State private var segmentPlaybackRates: [String: Double] = [:]
    @State private var segmentTranslationVisibility: [String: Bool] = [:]
    @State private var loopingSegmentID: String?
    
    var body: some View {
        Group {
            if !favoriteSegments.isEmpty {
                segmentList
            }
        }
        .onAppear(perform: syncFavorites)
        .onChange(of: favoriteSegmentsData.count) { _, _ in syncFavorites() }
        .onDisappear {
            segmentPlayer?.stop()
        }
    }
}

private extension FavoriteSegmentsView {
    var segmentList: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(Array(favoriteSegments.enumerated()), id: \.element.id) { index, segment in
                FavoriteSegmentCardView(
                    segment: segment,
                    segmentNumber: index + 1,
                    totalSegments: favoriteSegments.count,
                    currentPlayer: segmentPlayer,
                    isPlaying: segmentPlayer?.segmentId == segment.id && segmentPlayer?.isPlaying == true,
                    playbackRate: segmentPlaybackRates[segment.id] ?? 1.0,
                    isLooping: loopingSegmentID == segment.id,
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
                    onToggleLoop: {
                        if loopingSegmentID == segment.id {
                            loopingSegmentID = nil
                            if segmentPlayer?.segmentId == segment.id {
                                segmentPlayer?.isLooping = false
                            }
                        } else {
                            loopingSegmentID = segment.id
                            if let current = segmentPlayer, current.segmentId == segment.id {
                                current.isLooping = true
                            } else {
                                segmentPlayer?.isLooping = false
                            }
                            let isCurrentlyPlaying = segmentPlayer?.segmentId == segment.id && segmentPlayer?.isPlaying == true
                            if !isCurrentlyPlaying {
                                startPlayback(for: segment)
                            }
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
        .padding(.bottom, 32)
    }

    func syncFavorites() {
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
        if let loopingSegmentID, !ids.contains(loopingSegmentID) {
            self.loopingSegmentID = nil
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
            player.isLooping = loopingSegmentID == segment.id
            let didPrepare = await player.prepareAndPlay(playbackRate: rate)
            if !didPrepare {
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
    let isLooping: Bool
    let isTranslationVisible: Bool
    let onPlay: () -> Void
    let onUnfavorite: () -> Void
    let onRateChange: (Double) -> Void
    let onToggleLoop: () -> Void
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
                isLooping: isLooping,
                onUnfavorite: onUnfavorite,
                onRateChange: onRateChange,
                onToggleLoop: onToggleLoop
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

// MARK: - Favorite Segment Controls
private struct FavoriteSegmentControls: View {
    let playbackRate: Double
    let isLooping: Bool
    let onUnfavorite: () -> Void
    let onRateChange: (Double) -> Void
    let onToggleLoop: () -> Void

    private let rateOptions: [Double] = [0.75, 1.0, 1.5, 2.0]

    private func nextRate() -> Double {
        guard let currentIndex = rateOptions.firstIndex(of: playbackRate) else {
            return rateOptions[0]
        }
        let nextIndex = (currentIndex + 1) % rateOptions.count
        return rateOptions[nextIndex]
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            Button(action: onToggleLoop) {
                Image(systemName: "repeat")
                    .font(.body)
                    .foregroundColor(isLooping ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)

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
    var isLooping = false
    var playbackRate: Double = 1.0 {
        didSet {
            updatePlayerRate()
        }
    }
    
    @ObservationIgnored private var boundaryObserver: Any?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var audioPlayer: AVPlayer?
    @ObservationIgnored private var playbackFinishedObserver: AnyCancellable?
    
    init(segment: FavoritePodcastSegment) {
        self.segment = segment
        self.segmentId = segment.id
    }
    
    deinit {
        cleanup()
    }
    
    func prepareAndPlay(playbackRate: Double) async -> Bool {
        self.playbackRate = playbackRate
        do {
            setupAudioSession()
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
        let needsSeek = currentSeconds < segment.startTime || currentSeconds >= segment.endTime
        
        if needsSeek {
            let startTime = CMTime(seconds: segment.startTime, preferredTimescale: 600)
            player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                guard finished else { return }
                self?.startPlayback()
            }
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        guard let player = audioPlayer else { return }
        let endTime = CMTime(seconds: segment.endTime, preferredTimescale: 600)
        player.currentItem?.forwardPlaybackEndTime = endTime
        attachObservers()
        player.play()
        player.rate = Float(playbackRate)
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
        removeObservers()
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
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    private func setupLocalPlayer(with url: URL) {
        cleanup()
        audioPlayer = AVPlayer(url: url)
        audioPlayer?.actionAtItemEnd = .pause
    }

    private func attachObservers() {
        removeObservers()
        guard let player = audioPlayer else { return }
        let endTime = CMTime(seconds: segment.endTime, preferredTimescale: 600)
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) { [weak self] in
            self?.handleSegmentEnd()
        }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            if time.seconds >= self.segment.endTime {
                self.handleSegmentEnd()
            }
        }
        playbackFinishedObserver = NotificationCenter.default
            .publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                self?.handleSegmentEnd()
            }
    }

    private func handleSegmentEnd() {
        audioPlayer?.pause()
        removeObservers()
        guard let player = audioPlayer else {
            isPlaying = false
            return
        }
        let startTime = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self else { return }
            guard finished else {
                self.isPlaying = false
                return
            }
            if self.isLooping {
                self.startPlayback()
            } else {
                self.isPlaying = false
            }
        }
    }
    
    private func cleanup() {
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
        removeObservers()
        audioPlayer?.pause()
        audioPlayer = nil
        isPlaying = false
    }

    private func removeObservers() {
        if let boundaryObserver, let player = audioPlayer {
            player.removeTimeObserver(boundaryObserver)
        }
        boundaryObserver = nil
        if let timeObserver, let player = audioPlayer {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, options: [.allowBluetoothA2DP])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
}
