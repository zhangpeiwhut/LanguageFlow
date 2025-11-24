//
//  FavoritesView.swift
//  LanguageFlow
//

import SwiftUI
import SwiftData
import AVFoundation
import Observation
import Combine

struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavoritePodcast.createdAt, order: .reverse) private var favoritePodcastsData: [FavoritePodcast]
    @Query(sort: \FavoriteSegment.createdAt, order: .reverse) private var favoriteSegmentsData: [FavoriteSegment]
    @State private var favoritePodcasts: [FavoritePodcast] = []
    @State private var favoriteSegments: [FavoritePodcastSegment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var segmentPlayer: SegmentInlinePlayer?
    @State private var segmentPlaybackRates: [String: Double] = [:]
    @State private var segmentTranslationVisibility: [String: Bool] = [:]
    @State private var selectedTab: FavoritesTab = .podcasts
    @State private var presentingPodcast: FavoritePodcast?
    @State private var podcastDetails: [String: Podcast] = [:]
    @State private var loadingPodcastIds: Set<String> = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                tabSelector
                TabView(selection: $selectedTab) {
                    podcastsTab
                        .tag(FavoritesTab.podcasts)
                    segmentsTab
                        .tag(FavoritesTab.segments)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear(perform: loadFavorites)
            .onChange(of: favoriteSegmentsData.count) { _, _ in loadFavorites() }
            .onChange(of: favoritePodcastsData.count) { _, _ in loadFavorites() }
            .onDisappear {
                segmentPlayer?.stop()
            }
            .fullScreenCover(item: $presentingPodcast) { podcast in
                PodcastLearningView(podcastId: podcast.id)
            }
        }
    }
}

private enum FavoritesTab: Hashable, CaseIterable {
    case podcasts
    case segments

    var title: String {
        switch self {
        case .podcasts:
            return "整篇"
        case .segments:
            return "单句"
        }
    }
}

private extension FavoritesView {
    var tabSelector: some View {
        HStack(spacing: 10) {
            ForEach(FavoritesTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedTab == tab ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedTab == tab ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    var podcastsTab: some View {
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
                                        } catch {
                                            print("取消收藏失败: \(error)")
                                        }
                                    }
                                }
                            )
                            .task {
                                await loadPodcastDetailIfNeeded(for: podcast)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
    }

    var segmentsTab: some View {
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
                        loadFavorites()
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

    @MainActor
    func loadFavorites() {
        errorMessage = nil
        favoritePodcasts = favoritePodcastsData
        favoriteSegments = favoriteSegmentsData.map { $0.toFavoritePodcastSegment() }
        let podcastIds = Set(favoritePodcasts.map(\.id))
        podcastDetails = podcastDetails.filter { podcastIds.contains($0.key) }
        loadingPodcastIds = Set(loadingPodcastIds.filter { podcastIds.contains($0) })
        Task {
            await loadPodcastDetailsIfNeeded()
        }
        // 清理和补充本地状态缓存
        let ids = Set(favoriteSegments.map(\.id))
        segmentPlaybackRates = segmentPlaybackRates.filter { ids.contains($0.key) }
        segmentTranslationVisibility = segmentTranslationVisibility.filter { ids.contains($0.key) }
        for id in ids {
            if segmentPlaybackRates[id] == nil { segmentPlaybackRates[id] = 1.0 }
            if segmentTranslationVisibility[id] == nil { segmentTranslationVisibility[id] = true }
        }
        
        // 如果当前播放的段落被移除，则停止播放器
        if let currentId = segmentPlayer?.segmentId, !ids.contains(currentId) {
            segmentPlayer?.stop()
            segmentPlayer = nil
        }
    }

    @MainActor
    func loadPodcastDetailsIfNeeded() async {
        for podcast in favoritePodcasts {
            await loadPodcastDetailIfNeeded(for: podcast)
        }
    }

    @MainActor
    func loadPodcastDetailIfNeeded(for podcast: FavoritePodcast) async {
        guard podcastDetails[podcast.id] == nil,
              !loadingPodcastIds.contains(podcast.id) else { return }
        loadingPodcastIds.insert(podcast.id)
        do {
            let detail = try await PodcastAPI.shared.getPodcastDetailById(podcast.id)
            podcastDetails[podcast.id] = detail
        } catch {
            print("加载收藏Podcast详情失败: \(error)")
        }
        loadingPodcastIds.remove(podcast.id)
    }

    func durationText(for podcast: FavoritePodcast) -> String {
        guard let detail = podcastDetails[podcast.id] else {
            return "加载中..."
        }
        let totalSeconds = detail.segments.last?.end ?? 0
        guard totalSeconds > 0 else {
            return "未知时长"
        }
        let minutes = max(Int(ceil(totalSeconds / 60)), 1)
        return "\(minutes)分钟"
    }

    func segmentText(for podcast: FavoritePodcast) -> String {
        guard let detail = podcastDetails[podcast.id] else {
            return "加载中..."
        }
        let count = detail.segments.count
        return "\(count)句"
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
    
    private func setupLocalPlayer(with localAudioURL: URL) {
        cleanup()
        let playerItem = AVPlayerItem(url: localAudioURL)
        let player = AVPlayer(playerItem: playerItem)
        self.audioPlayer = player
        setupAudioSession()
        seekToSegmentStart()
        setupTimeObserver(for: player)
        setupFinishObserver(for: player)
    }
    
    private func setupFinishObserver(for player: AVPlayer) {
        if let currentItem = player.currentItem {
            playbackFinishedObserver = NotificationCenter.default
                .publisher(for: .AVPlayerItemDidPlayToEndTime, object: currentItem)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    self.isPlaying = false
                    self.seekToSegmentStart()
                }
        }
    }

    private func setupTimeObserver(for player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            if time.seconds >= self.segment.endTime {
                self.stop()
                self.seekToSegmentStart()
            }
        }
    }

    private func seekToSegmentStart() {
        guard let player = audioPlayer else { return }
        let startTime = CMTime(seconds: segment.startTime, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
    
    private func cleanup() {
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        audioPlayer?.pause()
        audioPlayer = nil
    }
}

#Preview {
    FavoritesView()
}
