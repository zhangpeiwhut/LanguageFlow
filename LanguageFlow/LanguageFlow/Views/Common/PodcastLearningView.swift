//
//  PodcastLearningView.swift
//  LanguageFlow
//

import SwiftUI
import Combine
import Observation
import AVFoundation
import AVFAudio
import SwiftData

struct PodcastLearningView: View {
    let podcastId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var store: PodcastLearningStore?

    init(podcastId: String) {
        self.podcastId = podcastId
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
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
                            loadPodcast()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let store = store {
                    VStack(spacing: 0) {
                        HStack(alignment: .center, spacing: 10) {
                            backButton
                            Text(store.podcast.title ?? "Podcast")
                                .font(.headline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .background(.ultraThinMaterial)
                        
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    SegmentListView(store: store)
                                }
                                .padding(.top, 8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 44)
                            }
                            .background(Color(.systemGroupedBackground))
                            .onChange(of: store.currentSegmentID) { _, newValue in
                                guard let id = newValue else { return }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                            .safeAreaInset(edge: .bottom) {
                                GlobalPlaybackBar(
                                    title: store.podcast.title ?? "Podcast",
                                    subtitle: store.podcast.subtitle ?? "",
                                    isPlaying: store.isGlobalPlaying,
                                    playbackRate: store.globalPlaybackRate,
                                    progressBinding: Binding(
                                        get: {
                                            guard store.totalDuration > 0 else { return 0 }
                                            return min(max(store.currentTime / store.totalDuration, 0), 1)
                                        },
                                        set: { store.jumpTo(progress: $0) }
                                    ),
                                    currentTime: store.currentTime,
                                    duration: store.totalDuration,
                                    onTogglePlay: store.toggleGlobalPlayback,
                                    onChangeRate: store.changeGlobalPlaybackRate,
                                    onSeekEditingChanged: store.handleSeekEditingChanged,
                                    isFavorited: store.isGlobalFavorited,
                                    onToggleFavorite: store.toggleGlobalFavorite,
                                    isLooping: store.isLooping,
                                    areTranslationsHidden: store.areTranslationsHidden,
                                    onToggleLoopMode: store.toggleLoopMode,
                                    onToggleTranslations: store.toggleTranslationVisibility
                                )
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.clear.ignoresSafeArea())
                            }
                        }
                    }
                } else {
                    Text("未找到Podcast")
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            loadPodcast()
        }
    }
    
    private func loadPodcast() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                var podcast: Podcast
                if let cached = FavoriteManager.shared.cachedFavoritePodcast(podcastId, context: modelContext),
                   let cachedPodcast = cached.toPodcast() {
                    podcast = cachedPodcast
                } else {
                    podcast = try await PodcastAPI.shared.getPodcastDetailById(podcastId)
                }

                var segments: [Podcast.Segment]
                if let cachedSegments = await SegmentCacheManager.shared.cachedSegments(forPodcastId: podcast.id) {
                    segments = cachedSegments
                } else {
                    let fetchedSegments = try await PodcastAPI.shared.loadSegments(from: podcast.segmentsTempURL)
                    try await SegmentCacheManager.shared.ensureSegmentsCached(forPodcastId: podcast.id, segments: fetchedSegments)
                    guard !fetchedSegments.isEmpty else {
                        throw NSError(domain: "PodcastLoadingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法加载segments数据"])
                    }
                    segments = fetchedSegments
                }

                guard !segments.isEmpty else {
                    throw NSError(domain: "PodcastLoadingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法加载segments数据"])
                }
                let localAudioURL = try await FavoriteManager.shared.ensureLocalAudio(for: podcast)
                store = PodcastLearningStore(
                    podcast: podcast,
                    segments: segments,
                    localAudioURL: localAudioURL,
                    modelContext: modelContext
                )
            } catch {
                errorMessage = error.localizedDescription
                print("加载podcast详情失败: \(error)")
            }
            isLoading = false
        }
    }
}

@Observable
final class PodcastLearningStore {
    var podcast: Podcast
    var segments: [Podcast.Segment]
    var isGlobalPlaying = false
    var globalPlaybackRate: Double = 1.0
    var isGlobalFavorited: Bool
    var currentSegmentID: Podcast.Segment.ID?
    var segmentStates: [Podcast.Segment.ID: SegmentPracticeState] = [:]
    var currentTime: Double = 0
    var isLooping = false
    var areTranslationsHidden = false

    @ObservationIgnored private var modelContext: ModelContext
    @ObservationIgnored private var playbackTimer: AnyCancellable?
    @ObservationIgnored private var audioPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var playbackFinishedObserver: AnyCancellable?
    @ObservationIgnored private var isGlobalMode = false
    @ObservationIgnored private var shouldResumeAfterSeek = false
    @ObservationIgnored private var isScrubbing = false
    @ObservationIgnored private let localAudioURL: URL

    init(podcast: Podcast, segments: [Podcast.Segment], localAudioURL: URL, modelContext: ModelContext) {
        self.podcast = podcast
        self.segments = segments
        self.modelContext = modelContext
        self.localAudioURL = localAudioURL
        let locallyFavorited = FavoriteManager.shared.isPodcastFavorited(podcast.id, context: modelContext)
        self.isGlobalFavorited = locallyFavorited || (podcast.status?.isFavorited ?? false)
        
        for segment in segments {
            let segmentId = "\(podcast.id)-\(segment.id)"
            let isSegmentFavorited = FavoriteManager.shared.isSegmentFavorited(segmentId, context: modelContext)
            segmentStates[segment.id] = SegmentPracticeState(
                playbackRate: segment.status?.customPlaybackRate ?? 1.0,
                isFavorited: isSegmentFavorited,
                lastScore: segment.status?.bestScore
            )
        }
        currentSegmentID = segments.first?.id
        if let firstSegment = segments.first {
            currentTime = firstSegment.start
        }
        setupAudioPlayer()
        setupAudioSession()
    }
    
    deinit {
        cleanupAudioPlayer()
    }
    
    func toggleGlobalPlayback() {
        if isGlobalPlaying {
            pauseAudio()
            isGlobalPlaying = false
            if isGlobalMode {
                isGlobalMode = false
            }
            setPlayingSegment(nil)
            return
        }
        isGlobalMode = true
        isGlobalPlaying = true
        setPlayingSegment(nil)
        
        if currentSegmentID == nil {
            currentSegmentID = segments.first?.id
        }
        playCurrentSegment()
    }

    func changeGlobalPlaybackRate(to rate: Double) {
        globalPlaybackRate = rate
        if isGlobalPlaying {
            audioPlayer?.rate = Float(rate)
        }
        for segment in segments {
            var state = segmentStates[segment.id] ?? SegmentPracticeState()
            state.playbackRate = rate
            segmentStates[segment.id] = state
        }
    }
    
    func toggleGlobalFavorite() {
        isGlobalFavorited.toggle()
        let shouldFavorite = isGlobalFavorited
        Task {
            do {
                if shouldFavorite {
                    try await FavoriteManager.shared.favoritePodcast(podcast, segments: segments, context: modelContext)
                } else {
                    try await FavoriteManager.shared.unfavoritePodcast(podcast.id, context: modelContext)
                }
            } catch {
                print("收藏整篇失败: \(error)")
                self.isGlobalFavorited.toggle()
            }
        }
    }

    func toggleLoopMode() {
        isLooping.toggle()
    }
    
    func toggleTranslationVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            areTranslationsHidden.toggle()
            if areTranslationsHidden {
                for segment in segments {
                    var state = segmentStates[segment.id] ?? SegmentPracticeState()
                    state.isTranslationVisible = false
                    segmentStates[segment.id] = state
                }
            } else {
                for segment in segments {
                    var state = segmentStates[segment.id] ?? SegmentPracticeState()
                    state.isTranslationVisible = true
                    segmentStates[segment.id] = state
                }
            }
        }
    }
    
    func toggleTranslation(for segment: Podcast.Segment) {
        var state = segmentStates[segment.id] ?? SegmentPracticeState()
        state.isTranslationVisible.toggle()
        segmentStates[segment.id] = state
    }

    func togglePlay(for segment: Podcast.Segment) {
        let isCurrentlyPlayingSegment = !isGlobalMode
            && isGlobalPlaying
            && currentSegmentID == segment.id

        if isCurrentlyPlayingSegment {
            playSegment(segment, useGlobalRate: false)
            return
        }

        isGlobalMode = false
        isGlobalPlaying = true
        currentSegmentID = segment.id
        setPlayingSegment(segment.id)
        playSegment(segment, useGlobalRate: false)
    }

    func toggleFavorite(for segment: Podcast.Segment) {
        var state = currentState(for: segment)
        let wasFavorited = state.isFavorited
        state.isFavorited.toggle()
        segmentStates[segment.id] = state
        
        Task {
            do {
                if state.isFavorited {
                    try await FavoriteManager.shared.favoriteSegment(
                        segment,
                        from: podcast,
                        context: modelContext
                    )
                } else {
                    let segmentId = "\(podcast.id)-\(segment.id)"
                    try await FavoriteManager.shared.unfavoriteSegment(segmentId, context: modelContext)
                }
            } catch {
                print("收藏单句失败: \(error)")
                var state = self.currentState(for: segment)
                state.isFavorited = wasFavorited
                self.segmentStates[segment.id] = state
            }
        }
    }

    func updatePlaybackRate(_ rate: Double, for segment: Podcast.Segment) {
        var state = currentState(for: segment)
        state.playbackRate = rate
        segmentStates[segment.id] = state
    }

    func updateAttempt(_ text: String, for segment: Podcast.Segment) {
        var state = currentState(for: segment)
        state.recognizedAttempt = text
        segmentStates[segment.id] = state
    }

    func handleSeekEditingChanged(isEditing: Bool) {
        if isEditing {
            beginScrubbing()
        } else {
            endScrubbing()
        }
    }

    func jumpTo(progress: Double) {
        guard totalDuration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        let rawTargetSeconds = clamped * totalDuration
        if audioPlayer == nil {
            setupAudioPlayer()
        }
        guard let player = audioPlayer else { return }
        currentTime = rawTargetSeconds
        if isScrubbing {
            if let targetSegment = segment(at: rawTargetSeconds), currentSegmentID != targetSegment.id {
                currentSegmentID = targetSegment.id
            }
            let seekTime = CMTime(seconds: rawTargetSeconds, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        isGlobalMode = true
        setPlayingSegment(nil)
        let targetSegment = segment(at: rawTargetSeconds)
        let seekSeconds = targetSegment?.start ?? rawTargetSeconds
        if let segment = targetSegment, currentSegmentID != segment.id {
            currentSegmentID = segment.id
        }
        currentTime = seekSeconds
        let seekTime = CMTime(seconds: seekSeconds, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished, let self = self else { return }
            self.currentTime = seekSeconds
            if let finalSegment = self.segment(at: seekSeconds), self.currentSegmentID != finalSegment.id {
                self.currentSegmentID = finalSegment.id
            }
            if self.isGlobalPlaying {
                player.rate = Float(self.globalPlaybackRate)
                player.play()
            }
        }
    }

    var currentSegmentIndex: Int? {
        guard
            let currentID = currentSegmentID,
            let index = segments.firstIndex(where: { $0.id == currentID })
        else {
            return nil
        }
        return index
    }
    
    var totalDuration: Double {
        guard let lastSegment = segments.last else {
            return 0
        }
        return lastSegment.end
    }

    private func currentState(for segment: Podcast.Segment) -> SegmentPracticeState {
        segmentStates[segment.id] ?? SegmentPracticeState()
    }

    private func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        shouldResumeAfterSeek = isGlobalMode && isGlobalPlaying
        if isGlobalPlaying || audioPlayer?.timeControlStatus == .playing {
            pauseAudio()
            isGlobalPlaying = false
        }
    }
    
    private func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        let shouldResume = shouldResumeAfterSeek
        shouldResumeAfterSeek = false
        if let targetSegment = segment(at: currentTime) {
            currentSegmentID = targetSegment.id
        }
        if shouldResume {
            isGlobalMode = true
            isGlobalPlaying = true
            setPlayingSegment(nil)
            playCurrentSegment()
        } else {
            isGlobalPlaying = false
            setPlayingSegment(nil)
        }
    }

    private func setupAudioPlayer() {
        audioPlayer = AVPlayer(url: localAudioURL)
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
    
    private func cleanupAudioPlayer() {
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
        timeObserver.map { audioPlayer?.removeTimeObserver($0) }
        timeObserver = nil
        audioPlayer?.pause()
        audioPlayer = nil
    }
    
    private func audioDidFinishPlaying() {
        if isGlobalMode {
            advanceToNextSegment()
        } else {
            pauseAudio()
            isGlobalPlaying = false
            setPlayingSegment(nil)
        }
    }
    
    private func playCurrentSegment() {
        guard let currentID = currentSegmentID,
              let segment = segments.first(where: { $0.id == currentID }) else {
            return
        }
        playSegment(segment, useGlobalRate: true)
    }
    
    private func playSegment(_ segment: Podcast.Segment, useGlobalRate: Bool = false) {
        guard let player = audioPlayer else {
            setupAudioPlayer()
            guard audioPlayer != nil else { return }
            return playSegment(segment, useGlobalRate: useGlobalRate)
        }
        
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        playbackFinishedObserver?.cancel()
        
        let startTime = CMTime(seconds: segment.start, preferredTimescale: 600)
        
        let playbackRate = useGlobalRate ? globalPlaybackRate : (segmentStates[segment.id]?.playbackRate ?? 1.0)
        player.rate = Float(playbackRate)
        
        player.seek(to: startTime) { [weak self] finished in
            guard finished, let self = self else { return }
            player.play()
            self.currentTime = startTime.seconds
            self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self = self else { return }
                let currentSeconds = time.seconds
                self.currentTime = currentSeconds
                if self.isGlobalMode {
                    if let currentSegment = self.segments.first(where: {
                        currentSeconds >= $0.start && currentSeconds < $0.end 
                    }) {
                        if self.currentSegmentID != currentSegment.id {
                            self.currentSegmentID = currentSegment.id
                        }
                    }
                    if let lastSegment = self.segments.last,
                       currentSeconds >= lastSegment.end {
                        self.handleGlobalPlaybackCompletion(using: player)
                    }
                } else {
                    if currentSeconds >= segment.end {
                        player.pause()
                        if let observer = self.timeObserver {
                            player.removeTimeObserver(observer)
                            self.timeObserver = nil
                        }
                        self.audioDidFinishPlaying()
                    }
                }
            }
            
            if let currentItem = player.currentItem {
                self.playbackFinishedObserver = NotificationCenter.default
                    .publisher(for: .AVPlayerItemDidPlayToEndTime, object: currentItem)
                    .sink { [weak self] _ in
                        guard let self = self else { return }
                        guard let strongPlayer = self.audioPlayer else {
                            self.isGlobalPlaying = false
                            self.isGlobalMode = false
                            return
                        }
                        if self.isGlobalMode {
                            self.handleGlobalPlaybackCompletion(using: strongPlayer)
                        } else {
                            self.audioDidFinishPlaying()
                        }
                    }
            }
        }
    }
    
    private func pauseAudio() {
        audioPlayer?.pause()
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
        if let player = audioPlayer {
            currentTime = player.currentTime().seconds
        }
    }
    
    private func advanceToNextSegment() {
        guard
            let currentID = currentSegmentID,
            let index = segments.firstIndex(where: { $0.id == currentID })
        else {
            currentSegmentID = segments.first?.id
            if isGlobalMode && isGlobalPlaying {
                playCurrentSegment()
            }
            return
        }

        let nextIndex = (index + 1) % segments.count
        currentSegmentID = segments[nextIndex].id
        
        if isGlobalMode && isGlobalPlaying {
            playCurrentSegment()
        }
    }
    
    private func setPlayingSegment(_ segmentID: Podcast.Segment.ID?) {
        for segment in segments {
            var state = currentState(for: segment)
            state.isPlaying = (segment.id == segmentID)
            segmentStates[segment.id] = state
        }
    }
    
    private func handleGlobalPlaybackCompletion(using player: AVPlayer) {
        if isLooping {
            restartGlobalPlayback(using: player)
        } else {
            stopGlobalPlayback(using: player)
        }
    }
    
    private func restartGlobalPlayback(using player: AVPlayer) {
        guard let firstSegment = segments.first else { return }
        let startTime = CMTime(seconds: firstSegment.start, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self = self else { return }
            self.currentSegmentID = firstSegment.id
            self.currentTime = firstSegment.start
            self.isGlobalPlaying = true
            self.isGlobalMode = true
            player.rate = Float(self.globalPlaybackRate)
            player.play()
        }
    }
    
    private func stopGlobalPlayback(using player: AVPlayer) {
        player.pause()
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
        currentTime = min(player.currentTime().seconds, totalDuration)
        isGlobalPlaying = false
        isGlobalMode = false
    }
    
    private func segment(at time: Double) -> Podcast.Segment? {
        for segment in segments {
            if time >= segment.start && time <= segment.end {
                return segment
            }
        }
        return segments.last(where: { $0.start <= time }) ?? segments.first
    }
}
