//
//  ShadowingPracticeView.swift
//  LanguageFlow
//

import SwiftUI
import SwiftData
import AVFoundation
import Observation
import Combine
import Darwin

struct ShadowingPracticeView: View {
    let podcast: Podcast
    let segments: [Podcast.Segment]
    let localAudioURL: URL
    let modelContext: ModelContext
    let startSegmentID: Podcast.Segment.ID?

    @State private var store: ShadowingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastManager.self) private var toastManager

    init(
        podcast: Podcast,
        segments: [Podcast.Segment],
        localAudioURL: URL,
        modelContext: ModelContext,
        startSegmentID: Podcast.Segment.ID?
    ) {
        self.podcast = podcast
        self.segments = segments
        self.localAudioURL = localAudioURL
        self.modelContext = modelContext
        self.startSegmentID = startSegmentID

        let startIndex = segments.firstIndex(where: { $0.id == startSegmentID }) ?? 0
        _store = State(initialValue: ShadowingStore(
            podcast: podcast,
            segments: segments,
            localAudioURL: localAudioURL,
            modelContext: modelContext,
            startIndex: startIndex
        ))
    }

    var body: some View {
        TabView(selection: $store.currentSegmentIndex) {
            ForEach(Array(store.segments.enumerated()), id: \.element.id) { index, segment in
                ShadowingPage(
                    segment: segment,
                    index: index,
                    total: store.segments.count,
                    store: store
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: store.currentSegmentIndex) { _, _ in
            store.stopPlayback()
            store.stopComparePlayback()
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink {
                    RecitingPracticeView(
                        podcast: podcast,
                        segments: segments,
                        localAudioURL: localAudioURL
                    )
                } label: {
                    HStack(spacing: 6) {
                        Text("Step 2 · 跟读")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    store.toggleTranslationVisibility()
                } label: {
                    Image(systemName: store.areTranslationsHidden ? "lightbulb.slash" : "lightbulb")
                        .font(.system(size: 14))
                }
            }
        }
        .onAppear {
            store.toastManager = toastManager
        }
        .onDisappear {
            store.cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recitingDidComplete)) { _ in
            dismiss()
        }
    }
    
    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    store.goToPrevious()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("上一句")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(store.currentSegmentIndex > 0 ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.currentSegmentIndex == 0)
                .frame(width: UIScreen.main.bounds.width * 0.3 - 24)
                
                HoldToRecordButton(
                    isRecording: store.isRecording,
                    isScoring: store.isScoring || (store.segmentStates[store.segments[store.currentSegmentIndex].id]?.isScoring ?? false),
                    onStart: {
                        Task {
                            await store.startRecording()
                        }
                    },
                    onEnd: {
                        store.stopRecording()
                    }
                )
                .frame(maxWidth: .infinity)
                
                Button {
                    store.goToNext()
                } label: {
                    HStack(spacing: 8) {
                        Text("下一句")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(store.currentSegmentIndex < store.segments.count - 1 ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.currentSegmentIndex >= store.segments.count - 1)
                .frame(width: UIScreen.main.bounds.width * 0.3 - 24)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

private struct ShadowingPage: View {
    let segment: Podcast.Segment
    let index: Int
    let total: Int
    @Bindable var store: ShadowingStore

    private var state: ShadowingSegmentState {
        store.segmentStates[segment.id] ?? ShadowingSegmentState()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sentenceTextArea

                if let last = state.lastScore {
                    scoreArea(lastScore: last)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var sentenceTextArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("句子 \(index + 1)/\(total)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("时长 \(String(format: "%.1f", segment.end - segment.start))s")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineSpacing(8)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let translation = segment.translation, !translation.isEmpty {
                Text(translation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .blur(radius: store.areTranslationsHidden ? 6 : 0)
                    .animation(.easeInOut(duration: 0.2), value: store.areTranslationsHidden)
            }

            HStack(spacing: 12) {
                Button {
                    store.togglePlayCurrent()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: store.isPlayingOriginal && state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text(store.isPlayingOriginal && state.isPlaying ? "暂停" : "播放")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    store.stopPlayback()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("停止")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func scoreArea(lastScore: Float) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("练习成绩")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("在安静的环境使用耳机得分会更高喔")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                ScoreBadge(title: "本次", score: lastScore, color: scoreColor(for: lastScore))
            }

            if state.recordingURL != nil {
                Button {
                    store.toggleComparePlayback(at: index)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.badge.mic")
                            .font(.system(size: 16, weight: .semibold))
                        Text(store.isComparing && store.comparingSegmentID == segment.id ? "停止对比" : "原音 + 跟读")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isRecording || store.isScoring || state.isScoring)
            }

            if let comparison = state.waveformComparison {
                WaveformComparisonView(comparison: comparison)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func scoreColor(for score: Float) -> Color {
        switch score {
        case 90...100: return .green
        case 80..<90: return .blue
        case 70..<80: return .orange
        default: return .red
        }
    }
}

@Observable
final class ShadowingStore {
    let podcast: Podcast
    let segments: [Podcast.Segment]
    let localAudioURL: URL
    @ObservationIgnored let modelContext: ModelContext
    @ObservationIgnored var toastManager: ToastManager?

    var currentSegmentIndex: Int
    var isRecording: Bool = false
    var isPlayingOriginal: Bool = false
    var isScoring: Bool = false
    var isComparing: Bool = false
    var comparingSegmentID: Podcast.Segment.ID?
    var areTranslationsHidden: Bool = false
    var playbackProgress: Double = 0
    var segmentStates: [Podcast.Segment.ID: ShadowingSegmentState] = [:]

    var completedSegmentsCount: Int {
        segmentStates.values.filter { $0.bestScore != nil }.count
    }

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var playbackFinishedObserver: AnyCancellable?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var compareAudioEngine: AVAudioEngine?
    @ObservationIgnored private var compareRefNode: AVAudioPlayerNode?
    @ObservationIgnored private var compareUserNode: AVAudioPlayerNode?
    @ObservationIgnored private var compareLoadTask: Task<Void, Never>?
    @ObservationIgnored private var compareStopTask: Task<Void, Never>?
    @ObservationIgnored private var scoringTask: Task<Void, Never>?
    @ObservationIgnored private var scoringEngine: ShadowingScoringEngine?
    @ObservationIgnored private var playerVolumeBeforeRecording: Float = 1.0
    @ObservationIgnored private var isPaused: Bool = false
    @ObservationIgnored private var pausedSegment: Podcast.Segment?

    init(
        podcast: Podcast,
        segments: [Podcast.Segment],
        localAudioURL: URL,
        modelContext: ModelContext,
        startIndex: Int
    ) {
        self.podcast = podcast
        self.segments = segments
        self.localAudioURL = localAudioURL
        self.modelContext = modelContext
        self.currentSegmentIndex = max(0, min(startIndex, segments.count - 1))

        for segment in segments {
            segmentStates[segment.id] = ShadowingSegmentState(
                bestScore: segment.status?.bestScore.map { Float($0) }
            )
        }
    }

    func toggleTranslationVisibility() {
        withAnimation(.easeInOut(duration: 0.2)) {
            areTranslationsHidden.toggle()
        }
    }

    func goToPrevious() {
        let target = max(0, currentSegmentIndex - 1)
        stopPlayback()
        currentSegmentIndex = target
    }

    func goToNext() {
        let target = min(segments.count - 1, currentSegmentIndex + 1)
        stopPlayback()
        currentSegmentIndex = target
    }

    func togglePlayCurrent() {
        if isPlayingOriginal {
            pausePlayback()
        } else {
            if isPaused, let pausedSeg = pausedSegment, pausedSeg.id == segments[currentSegmentIndex].id {
                resumePlayback()
            } else {
                playSegment(at: currentSegmentIndex)
            }
        }
    }

    func playSegment(at index: Int) {
        guard segments.indices.contains(index) else { return }
        stopComparePlayback()
        if isRecording {
            let session = AVAudioSession.sharedInstance()
            if !canPlayReferenceDuringRecording(session: session) {
                ShadowingDebug.log("playSegment blocked during recording (no headphones/external output)")
                return
            }
        }
        activatePlaybackSessionIfNeeded()
        let segment = segments[index]
        playbackProgress = 0
        isPaused = false
        pausedSegment = segment

        if player == nil {
            player = AVPlayer(url: localAudioURL)
        }

        guard let player else { return }
        removePlayerObservers()

        let startTime = CMTime(seconds: segment.start, preferredTimescale: 600)
        let endTime = segment.end

        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished, let self else { return }
            player.play()
            self.isPlayingOriginal = true
            self.updatePlayingState(activeSegmentID: segment.id)
            self.attachTimeObserver(for: segment, player: player, startTime: startTime, endTime: endTime)
        }
    }

    func pausePlayback() {
        player?.pause()
        isPlayingOriginal = false
        isPaused = true
    }

    func resumePlayback() {
        guard let player = player, let segment = pausedSegment else { return }
        player.play()
        isPlayingOriginal = true
        isPaused = false
        updatePlayingState(activeSegmentID: segment.id)
    }

    func stopPlayback() {
        guard let player = player else {
            isPlayingOriginal = false
            playbackProgress = 0
            isPaused = false
            pausedSegment = nil
            updatePlayingState(activeSegmentID: nil)
            return
        }
        player.pause()
        removePlayerObservers()
        if let segment = segments[safe: currentSegmentIndex] {
            let startTime = CMTime(seconds: segment.start, preferredTimescale: 600)
            player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        isPlayingOriginal = false
        playbackProgress = 0
        isPaused = false
        pausedSegment = nil
        updatePlayingState(activeSegmentID: nil)
    }

    func toggleComparePlayback(at index: Int) {
        guard segments.indices.contains(index) else { return }
        let segment = segments[index]
        if isComparing, comparingSegmentID == segment.id {
            stopComparePlayback()
            return
        }
        startComparePlayback(at: index)
    }

    func cleanup() {
        stopComparePlayback()
        stopPlayback()
        recorder?.stop()
        recorder = nil
        scoringTask?.cancel()
        scoringEngine = nil
        removePlayerObservers()
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
    }

    private func attachTimeObserver(
        for segment: Podcast.Segment,
        player: AVPlayer,
        startTime: CMTime,
        endTime: TimeInterval
    ) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let duration = max(segment.end - segment.start, 0.001)
            let progress = (time.seconds - segment.start) / duration
            self.playbackProgress = min(max(progress, 0), 1)
            if time.seconds >= endTime {
                self.stopPlayback()
            }
        }

        if let currentItem = player.currentItem {
            playbackFinishedObserver = NotificationCenter.default
                .publisher(for: .AVPlayerItemDidPlayToEndTime, object: currentItem)
                .sink { [weak self] _ in
                    self?.stopPlayback()
                }
        }
    }

    private func removePlayerObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        playbackFinishedObserver?.cancel()
        playbackFinishedObserver = nil
    }

    private func updatePlayingState(activeSegmentID: Podcast.Segment.ID?) {
        for segment in segments {
            var state = segmentStates[segment.id] ?? ShadowingSegmentState()
            state.isPlaying = (segment.id == activeSegmentID)
            segmentStates[segment.id] = state
        }
    }

    private func updateScoringState(for segment: Podcast.Segment, isScoring: Bool) {
        var state = segmentStates[segment.id] ?? ShadowingSegmentState()
        state.isScoring = isScoring
        segmentStates[segment.id] = state
    }

    private func updateScoringState(forSegmentID segmentID: Podcast.Segment.ID, isScoring: Bool) {
        var state = segmentStates[segmentID] ?? ShadowingSegmentState()
        state.isScoring = isScoring
        segmentStates[segmentID] = state
    }

    private func activatePlaybackSessionIfNeeded() {
        guard !isRecording else { return }
        configureSessionForPlayback(reason: "activatePlaybackSessionIfNeeded")
    }
    
    func showErrorToast(_ message: String) {
        Task {
            toastManager?.show(
                message,
                icon: "cry",
                iconSource: .asset,
                iconSize: CGSize(width: 34, height: 34),
                duration: 1.2
            )
        }
    }
}

struct ShadowingSegmentState: Equatable {
    var lastScore: Float?
    var bestScore: Float?
    var recordingURL: URL?
    var waveformComparison: ShadowingWaveformComparison?
    var isPlaying: Bool = false
    var isScoring: Bool = false
}

// MARK: - common helper
private extension ShadowingStore {
    func canPlayReferenceDuringRecording(session: AVAudioSession) -> Bool {
        let outputs = session.currentRoute.outputs
        let outputDesc = outputs
            .map { "\($0.portType.rawValue)(\($0.portName))" }
            .joined(separator: ", ")
        let inputs = session.currentRoute.inputs
        let inputDesc = inputs
            .map { "\($0.portType.rawValue)(\($0.portName))" }
            .joined(separator: ", ")
        ShadowingDebug.log("audio route outputs=[\(outputDesc)] inputs=[\(inputDesc)]")

        for out in outputs {
            switch out.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio:
                return true
            default:
                continue
            }
        }
        return false
    }

    func preferNonBluetoothMicIfAvailable(session: AVAudioSession) {
        guard let availableInputs = session.availableInputs, !availableInputs.isEmpty else { return }

        if ShadowingDebug.enabled {
            let desc = availableInputs
                .map { "\($0.portType.rawValue)(\($0.portName))" }
                .joined(separator: ", ")
            ShadowingDebug.log("audio available inputs=[\(desc)]")
        }

        // Prefer wired mic > built-in mic, avoid Bluetooth HFP mic for better scoring quality.
        let preferred =
            availableInputs.first(where: { $0.portType == .headsetMic }) ??
            availableInputs.first(where: { $0.portType == .builtInMic })

        guard let preferred else { return }
        do {
            try session.setPreferredInput(preferred)
            ShadowingDebug.log("audio preferred input set: \(preferred.portType.rawValue)(\(preferred.portName))")
        } catch {
            ShadowingDebug.log("audio preferred input set failed: \(ShadowingDebug.describe(error))")
        }
    }

    func configureSessionForPlayback(reason: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            ShadowingDebug.log("audio session deactivate failed (\(reason)): \(ShadowingDebug.describe(error))")
        }
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            ShadowingDebug.log("audio session playback ok (\(reason)): category=\(session.category.rawValue) mode=\(session.mode.rawValue) outputVolume=\(session.outputVolume)")
        } catch {
            print("[ShadowingStore] reset audio session failed: \(error)")
            ShadowingDebug.log("audio session playback failed (\(reason)): \(ShadowingDebug.describe(error))")
        }
    }
}

// MARK: - recording
extension ShadowingStore {
    func startRecording() async {
        guard !isRecording, let segment = segments[safe: currentSegmentIndex] else { return }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            ShadowingDebug.log("record permission granted (cached)")
            beginRecording(for: segment)
        case .denied:
            ShadowingDebug.log("record permission denied")
            showErrorToast("麦克风权限未开启")
        case .undetermined:
            ShadowingDebug.log("record permission undetermined; requesting")
            await AVAudioApplication.requestRecordPermission()
        @unknown default:
            ShadowingDebug.log("record permission unknown; treating as denied")
            showErrorToast("麦克风权限未开启")
        }
    }

    func beginRecording(for segment: Podcast.Segment) {
        stopComparePlayback()
        let session = AVAudioSession.sharedInstance()
        let mediaVolumeBefore = session.outputVolume
        ShadowingDebug.log("beginRecording start: mediaOutputVolume=\(mediaVolumeBefore)")
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            ShadowingDebug.log("beginRecording deactivate before switch failed: \(ShadowingDebug.describe(error))")
        }

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setPreferredSampleRate(Double(FrillTFLiteEmbedder.sampleRate))
            try? session.setPreferredInputNumberOfChannels(1)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            preferNonBluetoothMicIfAvailable(session: session)
            ShadowingDebug.log("audio session record ok: category=\(session.category.rawValue) mode=\(session.mode.rawValue) outputVolume=\(session.outputVolume)")
        } catch {
            ShadowingDebug.log("beginRecording audio session failed: \(ShadowingDebug.describe(error))")
            showErrorToast("开启录音失败")
            return
        }

        let allowReferencePlayback = canPlayReferenceDuringRecording(session: session)
        if !allowReferencePlayback {
            stopPlayback()
            ShadowingDebug.log("beginRecording no headphones/external output; skip reference playback to avoid leakage")
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shadow-\(UUID().uuidString).caf")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Double(FrillTFLiteEmbedder.sampleRate),
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            newRecorder.prepareToRecord()
            let started = newRecorder.record()
            guard started else {
                ShadowingDebug.log("beginRecording recorder.record() returned false url=\(ShadowingDebug.fileSummary(url: url))")
                showErrorToast("开启录音失败")
                return
            }

            recorder = newRecorder
            isRecording = true
            ShadowingDebug.log("beginRecording recorder started: url=\(ShadowingDebug.fileSummary(url: url))")

            if player == nil {
                player = AVPlayer(url: localAudioURL)
            }
            playerVolumeBeforeRecording = player?.volume ?? 1.0

            if allowReferencePlayback {
                let targetVolume: Float = (mediaVolumeBefore <= 0.001) ? 0.0 : 0.65
                player?.volume = targetVolume
                ShadowingDebug.log("beginRecording playback volume set: target=\(targetVolume) prev=\(playerVolumeBeforeRecording)")
                playSegment(at: currentSegmentIndex)
            } else {
                player?.volume = 0
            }
        } catch {
            ShadowingDebug.log("beginRecording AVAudioRecorder init failed: \(ShadowingDebug.describe(error)) url=\(ShadowingDebug.fileSummary(url: url))")
            showErrorToast("开启录音失败")
        }
    }


    func stopRecording() {
        guard isRecording else { return }
        let stoppedRecorder = recorder
        let duration = stoppedRecorder?.currentTime ?? 0
        stoppedRecorder?.stop()
        let recordedURL = stoppedRecorder?.url
        recorder = nil
        isRecording = false
        stopPlayback()
        player?.volume = playerVolumeBeforeRecording
        configureSessionForPlayback(reason: "stopRecording")

        guard let url = recordedURL, let segment = segments[safe: currentSegmentIndex] else { return }
        let summary = ShadowingDebug.fileSummary(url: url)
        ShadowingDebug.log("recording stopped: duration=\(String(format: "%.3f", duration))s file=\(summary)")

        let minDuration: TimeInterval = 0.25
        if duration < minDuration {
            showErrorToast("录音时间太短，请再试一次")
            return
        }

        scoreRecording(url: url, for: segment)
    }

    func scoreRecording(url: URL, for segment: Podcast.Segment) {
        scoringTask?.cancel()
        isScoring = true
        updateScoringState(for: segment, isScoring: true)

        let segmentID = segment.id
        let segmentStart = segment.start
        let segmentEnd = segment.end
        let localAudioURL = self.localAudioURL
        ShadowingDebug.log("scoreRecording start: segment=\(segmentID) start=\(segmentStart) end=\(segmentEnd) ref=\(ShadowingDebug.fileSummary(url: localAudioURL)) user=\(ShadowingDebug.fileSummary(url: url))")

        scoringTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            do {
                let engine: ShadowingScoringEngine
                if let existing = await MainActor.run(body: { self.scoringEngine }) {
                    ShadowingDebug.log("scoreRecording engine: reuse")
                    engine = existing
                } else {
                    let created = try ShadowingScoringEngine(localAudioURL: localAudioURL)
                    await MainActor.run {
                        self.scoringEngine = created
                    }
                    ShadowingDebug.log("scoreRecording engine: created")
                    engine = created
                }

                let result = try await engine.score(
                    referenceStart: segmentStart,
                    referenceEnd: segmentEnd,
                    userAudioURL: url
                )

                await MainActor.run {
                    var state = self.segmentStates[segmentID] ?? ShadowingSegmentState()
                    state.lastScore = result.acousticScore
                    state.bestScore = max(result.acousticScore, state.bestScore ?? 0)
                    state.recordingURL = url
                    state.waveformComparison = result.waveformComparison
                    state.isScoring = false
                    self.segmentStates[segmentID] = state
                    self.isScoring = false
                }
                ShadowingDebug.log("scoreRecording success: segment=\(segmentID) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s")
            } catch is CancellationError {
                await MainActor.run {
                    self.updateScoringState(forSegmentID: segmentID, isScoring: false)
                    self.isScoring = false
                }
            } catch {
                await MainActor.run {
                    print("[ShadowingStore] scoring failed: \(error)")
                    // Show user-friendly error message if available
                    let message: String
                    if let nsError = error as? NSError, 
                       let desc = nsError.userInfo[NSLocalizedDescriptionKey] as? String,
                       !desc.isEmpty {
                        message = desc
                    } else {
                        message = "打分失败"
                    }
                    self.showErrorToast(message)
                    self.updateScoringState(forSegmentID: segmentID, isScoring: false)
                    self.isScoring = false
                }
                ShadowingDebug.log("scoreRecording failed: segment=\(segmentID) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startedAt)))s err=\(ShadowingDebug.describe(error))")
            }
        }
    }
}

// MARK: - play or stop (ref & user) audio
extension ShadowingStore {
    private func startComparePlayback(at index: Int) {
        guard
            let segment = segments[safe: index],
            let recordedURL = segmentStates[segment.id]?.recordingURL,
            !isRecording
        else { return }

        stopPlayback()
        stopComparePlayback()

        isComparing = true
        comparingSegmentID = segment.id
        configureSessionForPlayback(reason: "comparePlayback")

        let refURL = localAudioURL
        let refStart = segment.start
        let refEnd = segment.end

        compareLoadTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let refWave = try await AudioWaveLoader.loadMono(
                    from: refURL,
                    sampleRate: Double(FrillTFLiteEmbedder.sampleRate),
                    start: refStart,
                    end: refEnd
                )
                let userWave = try await AudioWaveLoader.loadMono(
                    from: recordedURL,
                    sampleRate: Double(FrillTFLiteEmbedder.sampleRate)
                )

                let refTrimInfo = AudioWaveLoader.trimSilenceWithInfo(
                    refWave,
                    sampleRate: FrillTFLiteEmbedder.sampleRate
                )
                let userTrimInfo = AudioWaveLoader.trimSilenceWithInfo(
                    userWave,
                    sampleRate: FrillTFLiteEmbedder.sampleRate
                )
                let refTrimmed = refTrimInfo.trimmed
                let userTrimmed = userTrimInfo.trimmed

                if ShadowingDebug.enabled {
                    let sr = Double(FrillTFLiteEmbedder.sampleRate)
                    let refHead = Double(refTrimInfo.start) / sr
                    let refTail = Double(max(0, refWave.count - 1 - refTrimInfo.end)) / sr
                    let userHead = Double(userTrimInfo.start) / sr
                    let userTail = Double(max(0, userWave.count - 1 - userTrimInfo.end)) / sr
                    ShadowingDebug.log("compare trim ref: head=\(String(format: "%.3f", refHead))s tail=\(String(format: "%.3f", refTail))s thr=\(String(format: "%.4f", refTrimInfo.threshold)) noiseE=\(String(format: "%.4f", refTrimInfo.noiseEnergy)) maxE=\(String(format: "%.4f", refTrimInfo.maxEnergy))")
                    ShadowingDebug.log("compare trim user: head=\(String(format: "%.3f", userHead))s tail=\(String(format: "%.3f", userTail))s thr=\(String(format: "%.4f", userTrimInfo.threshold)) noiseE=\(String(format: "%.4f", userTrimInfo.noiseEnergy)) maxE=\(String(format: "%.4f", userTrimInfo.maxEnergy))")
                }

                let align = alignForComparePlayback(
                    referenceWaveform: refTrimmed,
                    userWaveform: userTrimmed,
                    sampleRate: FrillTFLiteEmbedder.sampleRate
                )
                if ShadowingDebug.enabled {
                    // Positive offset means user lags (starts later); negative means user leads.
                    let applied = align.offsetSeconds > 0 ? "delayRef" : (align.offsetSeconds < 0 ? "delayUser" : "none")
                    ShadowingDebug.log("compare align lagFrames=\(align.lagFrames) offset=\(String(format: "%.3f", align.offsetSeconds))s corr=\(String(format: "%.3f", align.correlation)) applied=\(applied)")
                }

                await MainActor.run {
                    guard self.isComparing, self.comparingSegmentID == segment.id else { return }
                    self.playCompare(
                        refWaveform: refTrimmed,
                        userWaveform: userTrimmed,
                        segmentID: segment.id,
                        alignmentOffsetSeconds: align.offsetSeconds,
                        alignmentCorrelation: align.correlation
                    )
                }
            } catch {
                await MainActor.run {
                    guard self.isComparing, self.comparingSegmentID == segment.id else { return }
                    self.showErrorToast("播放失败")
                    self.stopComparePlayback()
                }
            }
        }
    }

    private func playCompare(
        refWaveform: [Float],
        userWaveform: [Float],
        segmentID: Podcast.Segment.ID,
        alignmentOffsetSeconds: Double,
        alignmentCorrelation: Float
    ) {
        guard !refWaveform.isEmpty, !userWaveform.isEmpty else {
            self.showErrorToast("播放失败")
            stopComparePlayback()
            return
        }

        let sr = Double(FrillTFLiteEmbedder.sampleRate)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sr,
            channels: 1,
            interleaved: false
        ) else {
            self.showErrorToast("播放失败")
            stopComparePlayback()
            return
        }

        guard let refBuffer = makePCMBuffer(from: refWaveform, format: format),
              let userBuffer = makePCMBuffer(from: userWaveform, format: format) else {
            self.showErrorToast("播放失败")
            stopComparePlayback()
            return
        }

        let engine = AVAudioEngine()
        let refNode = AVAudioPlayerNode()
        let userNode = AVAudioPlayerNode()
        engine.attach(refNode)
        engine.attach(userNode)

        engine.connect(refNode, to: engine.mainMixerNode, format: format)
        engine.connect(userNode, to: engine.mainMixerNode, format: format)

        // Slightly lower reference volume so the user's voice is clearer.
        refNode.volume = 0.85
        userNode.volume = 1.0

        do {
            try engine.start()
        } catch {
            self.showErrorToast("播放失败")
            stopComparePlayback()
            return
        }

        compareAudioEngine = engine
        compareRefNode = refNode
        compareUserNode = userNode

        refNode.scheduleBuffer(refBuffer, at: nil, options: [])
        userNode.scheduleBuffer(userBuffer, at: nil, options: [])

        // Gate: if correlation is too low, don't force-align (it may make it worse).
        let minCorrToApply: Float = 0.14
        let rawOffset = (alignmentCorrelation >= minCorrToApply) ? alignmentOffsetSeconds : 0

        // alignmentOffsetSeconds > 0 => user lags => delay reference.
        // alignmentOffsetSeconds < 0 => user leads => delay user.
        let offset = max(-1.0, min(1.0, rawOffset))
        let delayRef = max(0, offset)
        let delayUser = max(0, -offset)

        if ShadowingDebug.enabled {
            ShadowingDebug.log(
                "compare play offset=\(String(format: "%.3f", offset))s corr=\(String(format: "%.3f", alignmentCorrelation)) apply=\(alignmentCorrelation >= minCorrToApply) delayRef=\(String(format: "%.3f", delayRef))s delayUser=\(String(format: "%.3f", delayUser))s"
            )
        }

        let baseHostTime = mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05)
        let refHostTime = baseHostTime + AVAudioTime.hostTime(forSeconds: delayRef)
        let userHostTime = baseHostTime + AVAudioTime.hostTime(forSeconds: delayUser)
        refNode.play(at: AVAudioTime(hostTime: refHostTime))
        userNode.play(at: AVAudioTime(hostTime: userHostTime))

        let refSeconds = Double(refWaveform.count) / sr + delayRef
        let userSeconds = Double(userWaveform.count) / sr + delayUser
        let seconds = max(refSeconds, userSeconds)
        compareStopTask?.cancel()
        compareStopTask = Task { [weak self] in
            let ns = UInt64((seconds + 0.15) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            await MainActor.run {
                guard let self else { return }
                guard self.isComparing, self.comparingSegmentID == segmentID else { return }
                self.stopComparePlayback()
            }
        }
    }

    private func makePCMBuffer(from waveform: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(waveform.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        waveform.withUnsafeBufferPointer { src in
            channel.update(from: src.baseAddress!, count: waveform.count)
        }
        return buffer
    }

    func stopComparePlayback() {
        compareLoadTask?.cancel()
        compareLoadTask = nil
        compareStopTask?.cancel()
        compareStopTask = nil

        compareRefNode?.stop()
        compareUserNode?.stop()
        compareAudioEngine?.stop()

        compareRefNode = nil
        compareUserNode = nil
        compareAudioEngine = nil

        isComparing = false
        comparingSegmentID = nil
    }

    nonisolated
    private func alignForComparePlayback(
        referenceWaveform: [Float],
        userWaveform: [Float],
        sampleRate: Int,
        frameMs: Double = 20,
        hopMs: Double = 10,
        maxLagSeconds: Double = 0.6
    ) -> (offsetSeconds: Double, correlation: Float, lagFrames: Int) {
        guard !referenceWaveform.isEmpty, !userWaveform.isEmpty else { return (0, 0, 0) }

        let sr = Double(sampleRate)
        let frame = max(1, Int(sr * frameMs / 1000.0))
        let hop = max(1, Int(sr * hopMs / 1000.0))
        let hopSeconds = Double(hop) / sr

        func energyEnvelope(_ waveform: [Float]) -> [Float] {
            guard waveform.count >= frame else { return [] }
            func meanAbs(at start: Int) -> Float {
                let end = min(waveform.count, start + frame)
                if start >= end { return 0 }
                var sum: Float = 0
                var n = 0
                for i in start..<end {
                    let x = waveform[i]
                    if x.isNaN || x.isInfinite { continue }
                    sum += abs(x)
                    n += 1
                }
                guard n > 0 else { return 0 }
                return sum / Float(n)
            }

            var out: [Float] = []
            out.reserveCapacity(max(1, waveform.count / hop))
            var s = 0
            while s < waveform.count {
                out.append(meanAbs(at: s))
                if s + frame >= waveform.count { break }
                s += hop
            }
            return out
        }

        func zScore(_ x: [Float]) -> [Float] {
            guard !x.isEmpty else { return [] }
            var mean: Double = 0
            for v in x { mean += Double(v) }
            mean /= Double(x.count)
            var varSum: Double = 0
            for v in x {
                let d = Double(v) - mean
                varSum += d * d
            }
            let std = sqrt(varSum / Double(x.count)) + 1e-6
            return x.map { Float((Double($0) - mean) / std) }
        }

        func corrAtLag(_ a: [Float], _ b: [Float], lag: Int) -> Float {
            var a0 = 0
            var b0 = 0
            if lag > 0 {
                b0 = lag
            } else if lag < 0 {
                a0 = -lag
            }
            let n = min(a.count - a0, b.count - b0)
            guard n > 3 else { return -Float.infinity }
            var sum: Float = 0
            for i in 0..<n { sum += a[a0 + i] * b[b0 + i] }
            return sum / Float(n)
        }

        let refE = energyEnvelope(referenceWaveform)
        let userE = energyEnvelope(userWaveform)
        guard refE.count > 8, userE.count > 8 else { return (0, 0, 0) }

        let refZ = zScore(refE)
        let userZ = zScore(userE)

        let maxLagFrames = min(
            Int(maxLagSeconds / max(hopSeconds, 1e-6)),
            max(0, min(refZ.count, userZ.count) - 4)
        )
        guard maxLagFrames > 0 else { return (0, 0, 0) }

        var bestLag = 0
        var bestCorr: Float = -Float.infinity
        for lag in (-maxLagFrames)...maxLagFrames {
            let c = corrAtLag(refZ, userZ, lag: lag)
            if c > bestCorr {
                bestCorr = c
                bestLag = lag
            }
        }

        if !bestCorr.isFinite { return (0, 0, 0) }
        let offsetSeconds = Double(bestLag) * hopSeconds
        return (offsetSeconds: offsetSeconds, correlation: bestCorr, lagFrames: bestLag)
    }
}
