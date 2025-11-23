//
//  PodcastLearningView.swift
//  LanguageFlow
//

import SwiftUI
import Combine
import Observation
import AVFoundation
import AVFAudio

struct PodcastLearningView: View {
    let podcastId: String
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var store: PodcastLearningStore?

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
                let loadedPodcast = try await PodcastAPI.shared.getPodcastDetailById(podcastId)
                store = PodcastLearningStore(podcast: loadedPodcast)
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
    var isGlobalPlaying = false
    var globalPlaybackRate: Double = 1.0
    var isGlobalFavorited: Bool
    var currentSegmentID: Podcast.Segment.ID?
    var segmentStates: [Podcast.Segment.ID: SegmentPracticeState] = [:]
    var currentTime: Double = 0
    var isLooping = false
    var areTranslationsHidden = false

    @ObservationIgnored private var playbackTimer: AnyCancellable?
    @ObservationIgnored private var audioPlayer: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var playbackFinishedObserver: AnyCancellable?
    @ObservationIgnored private var isGlobalMode = false
    @ObservationIgnored private var shouldResumeAfterSeek = false
    @ObservationIgnored private var isScrubbing = false

    init(podcast: Podcast) {
        self.podcast = podcast
        self.isGlobalFavorited = podcast.status?.isFavorited ?? false
        for segment in podcast.segments {
            segmentStates[segment.id] = SegmentPracticeState(
                playbackRate: segment.status?.customPlaybackRate ?? 1.0,
                isFavorited: segment.status?.isFavorited ?? false,
                lastScore: segment.status?.bestScore
            )
        }
        currentSegmentID = podcast.segments.first?.id
        if let firstSegment = podcast.segments.first {
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
            currentSegmentID = podcast.segments.first?.id
        }
        playCurrentSegment()
    }

    func changeGlobalPlaybackRate(to rate: Double) {
        globalPlaybackRate = rate
        if isGlobalPlaying {
            audioPlayer?.rate = Float(rate)
        }
        for segment in podcast.segments {
            var state = segmentStates[segment.id] ?? SegmentPracticeState()
            state.playbackRate = rate
            segmentStates[segment.id] = state
        }
    }
    
    func toggleGlobalFavorite() {
        isGlobalFavorited.toggle()
    }
    
    func toggleLoopMode() {
        isLooping.toggle()
    }
    
    func toggleTranslationVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            areTranslationsHidden.toggle()
            if areTranslationsHidden {
                for segment in podcast.segments {
                    var state = segmentStates[segment.id] ?? SegmentPracticeState()
                    state.isTranslationVisible = false
                    segmentStates[segment.id] = state
                }
            } else {
                for segment in podcast.segments {
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
        state.isFavorited.toggle()
        segmentStates[segment.id] = state
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
            let index = podcast.segments.firstIndex(where: { $0.id == currentID })
        else {
            return nil
        }
        return index
    }
    
    var totalDuration: Double {
        guard let lastSegment = podcast.segments.last else {
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
        guard let audioURL = URL(string: podcast.audioURL), audioURL.scheme != nil else { return }
        audioPlayer = AVPlayer(url: audioURL)
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
              let segment = podcast.segments.first(where: { $0.id == currentID }) else {
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
                    if let currentSegment = self.podcast.segments.first(where: {
                        currentSeconds >= $0.start && currentSeconds < $0.end 
                    }) {
                        if self.currentSegmentID != currentSegment.id {
                            self.currentSegmentID = currentSegment.id
                        }
                    }
                    if let lastSegment = self.podcast.segments.last,
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
            let index = podcast.segments.firstIndex(where: { $0.id == currentID })
        else {
            currentSegmentID = podcast.segments.first?.id
            if isGlobalMode && isGlobalPlaying {
                playCurrentSegment()
            }
            return
        }

        let nextIndex = (index + 1) % podcast.segments.count
        currentSegmentID = podcast.segments[nextIndex].id
        
        if isGlobalMode && isGlobalPlaying {
            playCurrentSegment()
        }
    }
    
    private func setPlayingSegment(_ segmentID: Podcast.Segment.ID?) {
        for segment in podcast.segments {
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
        guard let firstSegment = podcast.segments.first else { return }
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
        for segment in podcast.segments {
            if time >= segment.start && time <= segment.end {
                return segment
            }
        }
        return podcast.segments.last(where: { $0.start <= time }) ?? podcast.segments.first
    }
}
