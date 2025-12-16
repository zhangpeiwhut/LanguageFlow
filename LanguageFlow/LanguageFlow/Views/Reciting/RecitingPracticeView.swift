//
//  RecitingPracticeView.swift
//  LanguageFlow
//

import SwiftUI
import SwiftData
import Foundation
import Speech
import AVFoundation
import Observation

struct RecitingPracticeView: View {
    let podcast: Podcast
    let segments: [Podcast.Segment]
    let localAudioURL: URL

    @State private var store: RecitingStore

    init(
        podcast: Podcast,
        segments: [Podcast.Segment],
        localAudioURL: URL,
    ) {
        self.podcast = podcast
        self.segments = segments
        self.localAudioURL = localAudioURL
        _store = State(initialValue: RecitingStore(podcast: podcast, segments: segments))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.phase == .preview {
                        Text(store.fullText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineSpacing(8)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(0..<store.visibleSentenceCount, id: \.self) { index in
                                    let parts = store.sentenceDisplayParts(sentenceIndex: index)
                                    (Text(parts.revealedText) +
                                     Text(parts.hintText)
                                        .foregroundStyle(.secondary.opacity(0.55)) +
                                     Text(parts.hiddenText)
                                        .foregroundStyle(Color.clear))
                                    .font(.title3.weight(.semibold))
                                    .lineSpacing(10)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .id(ScrollAnchor.sentence(index))
                                }
                            }

                            if store.shouldShowRecitingPlaceholder {
                                Text("开始背诵吧")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    if store.phase != .preview, RecitingDebug.enabled {
                        VStack(alignment: .leading, spacing: 6) {
                            if !store.debugStatusLine.isEmpty {
                                Text(store.debugStatusLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !store.lastPartialText.isEmpty {
                                Text(store.lastPartialText)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ScrollAnchor.bottom)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: store.phase) { _, newValue in
                guard newValue == .reciting else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(ScrollAnchor.sentence(0), anchor: .top)
                }
            }
            .onChange(of: store.currentSentenceIndex) { _, newValue in
                guard store.phase != .preview else { return }
                guard newValue >= 0, newValue < store.visibleSentenceCount else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(ScrollAnchor.sentence(newValue), anchor: .top)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Step 3 · 背诵")
                    .font(.headline)
            }
        }
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { newValue in
                if !newValue { store.errorMessage = nil }
            }
        )) {
            Button("好的", role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            if let message = store.errorMessage {
                Text(message)
            }
        }
        .onDisappear {
            store.cleanup()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if store.phase == .preview {
                Button {
                    Task { await store.startReciting() }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("开始背诵")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(store.isStarting ? Color.gray : Color.accentColor)
                    )
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(store.isStarting)
            } else {
                recognitionStrip

                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            store.showHint()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("提示")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
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
                        .disabled(!store.canShowHint)

                        Button {
                            store.skipNextWord()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "forward.end")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("跳过")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
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
                        .disabled(!store.canSkip)
                    }
                    .frame(maxWidth: .infinity)

                    Button(role: .destructive) {
                        Task { await store.stopReciting(resetToPreview: true) }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("结束")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer(minLength: 0)
                            Text(store.elapsedTimeText)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.red)
                        )
                        .shadow(color: Color.red.opacity(0.2), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var recognitionStrip: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(recognitionIndicatorColor(for: store.recognitionState))
                .frame(width: 8, height: 8)

            if !store.recentRecognizedDisplayText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(store.recentRecognizedDisplayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private enum ScrollAnchor {
        static let bottom = "reciting-bottom"

        static func sentence(_ index: Int) -> String {
            "reciting-sentence-\(index)"
        }
    }

    private func recognitionIndicatorColor(for state: RecitingStore.RecognitionState) -> Color {
        switch state {
        case .idle:
            return Color.secondary.opacity(0.5)
        case .preparing:
            return .orange
        case .listening:
            return .green
        case .error:
            return .red
        }
    }
}

@Observable
final class RecitingStore {
    enum Phase: Equatable {
        case preview
        case reciting
    }

    enum RecognitionState: Equatable {
        case idle
        case preparing
        case listening
        case error
    }

    let podcast: Podcast
    let segments: [Podcast.Segment]

    var phase: Phase = .preview
    var recognitionState: RecognitionState = .idle
    var engineName: String = ""
    var errorMessage: String?
    var isStarting: Bool = false
    var revealedTokenCount: Int = 0
    var hintEndTokenIndex: Int?
    var elapsedSeconds: Int = 0
    var lastPartialText: String = ""
    var lastCommittedWordsText: String = ""
    var recentRecognizedWords: [String] = []
    var recentPartialWords: [String] = []
    var lastRecognitionEventAt: Date?
    var matchedWordCount: Int = 0
    var mismatchCount: Int = 0
    var skippedWordCount: Int = 0

    var fullText: String {
        transcriptText
    }

    var elapsedTimeText: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var canShowHint: Bool {
        guard phase != .preview else { return false }
        return nextWordTokenIndex(from: revealedTokenCount) != nil
    }

    var canSkip: Bool {
        guard phase != .preview else { return false }
        return nextWordTokenIndex(from: revealedTokenCount) != nil
    }

    var debugStatusLine: String {
        guard phase != .preview else { return "" }
        var parts: [String] = []
        if !engineName.isEmpty {
            parts.append(engineName)
        }
        parts.append(recognitionStateText)
        parts.append("reveal \(revealedTokenCount)/\(tokens.count)")
        if wordTokenTotal > 0 {
            parts.append("matched \(matchedWordCount)/\(wordTokenTotal)")
        }
        if mismatchCount > 0 {
            parts.append("mismatch \(mismatchCount)")
        }
        if skippedWordCount > 0 {
            parts.append("skip \(skippedWordCount)")
        }
        if let next = debugNextExpectedWord, !next.isEmpty {
            parts.append("next \(next)")
        } else {
            parts.append("done")
        }
        if let lastRecognitionEventAt {
            parts.append("last \(max(0, Int(Date().timeIntervalSince(lastRecognitionEventAt))))s")
        }
        if !lastCommittedWordsText.isEmpty {
            parts.append("commit \(RecitingDebug.truncate(lastCommittedWordsText, limit: 42))")
        }
        return parts.joined(separator: " · ")
    }

    private var debugNextExpectedWord: String? {
        guard phase != .preview else { return nil }
        guard let idx = nextWordTokenIndex(from: revealedTokenCount) else { return nil }
        return tokens[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var shouldShowRecitingPlaceholder: Bool {
        phase != .preview && revealedTokenCount == 0 && hintEndTokenIndex == nil && mismatchCount == 0
    }

    var sentenceCount: Int {
        sentenceTokenRanges.count
    }

    var visibleSentenceCount: Int {
        guard phase != .preview else { return sentenceCount }
        guard sentenceCount > 0 else { return 0 }

        var maxIndex = currentSentenceIndex
        if let hintEndTokenIndex {
            let tokenIndex = max(0, hintEndTokenIndex - 1)
            if let hintSentenceIndex = sentenceIndex(containing: tokenIndex) {
                maxIndex = max(maxIndex, hintSentenceIndex)
            }
        }
        return min(sentenceCount, maxIndex + 1)
    }

    var recentRecognizedDisplayText: String {
        if !recentRecognizedWords.isEmpty {
            return recentRecognizedWords.joined(separator: " ")
        }
        if !recentPartialWords.isEmpty {
            return recentPartialWords.joined(separator: " ")
        }
        return ""
    }

    var currentSentenceIndex: Int {
        guard phase != .preview else { return 0 }
        let tokenIndex: Int
        if let next = nextWordTokenIndex(from: revealedTokenCount) {
            tokenIndex = next
        } else {
            tokenIndex = max(0, tokens.count - 1)
        }
        return sentenceIndex(containing: tokenIndex) ?? 0
    }

    func sentenceDisplayParts(sentenceIndex: Int) -> (revealedText: String, hintText: String, hiddenText: String) {
        guard sentenceTokenRanges.indices.contains(sentenceIndex) else { return ("", "", "") }
        let range = sentenceTokenRanges[sentenceIndex]

        let safeReveal = max(0, min(revealedTokenCount, tokens.count))
        let safeHintEnd = max(safeReveal, min(hintEndTokenIndex ?? safeReveal, tokens.count))

        let revealedStart = range.lowerBound
        let revealedEnd = min(safeReveal, range.upperBound)

        let hintStart = max(safeReveal, range.lowerBound)
        let hintEnd = min(safeHintEnd, range.upperBound)

        let hiddenStart = max(safeHintEnd, range.lowerBound)
        let hiddenEnd = range.upperBound

        let revealedText = (revealedEnd > revealedStart) ? tokens[revealedStart..<revealedEnd].map(\.text).joined() : ""
        let hintText = (hintEnd > hintStart) ? tokens[hintStart..<hintEnd].map(\.text).joined() : ""
        let hiddenText = (hiddenEnd > hiddenStart) ? tokens[hiddenStart..<hiddenEnd].map(\.text).joined() : ""
        return (revealedText, hintText, hiddenText)
    }

    private let transcriptText: String
    private let tokens: [RecitationToken]
    private let sentenceEndTokenIndices: [Int]
    private let sentenceTokenRanges: [Range<Int>]
    private let wordTokenTotal: Int
    @ObservationIgnored private var recognizerEngine: (any LiveSpeechRecognizerEngine)?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var startDate: Date?

    init(podcast: Podcast, segments: [Podcast.Segment]) {
        self.podcast = podcast
        self.segments = segments

        let tokenization = RecitationTokenizer.tokenizeSentences(segments.map(\.text))
        self.transcriptText = tokenization.transcriptText
        self.tokens = tokenization.tokens
        self.sentenceEndTokenIndices = tokenization.sentenceEndTokenIndices
        self.sentenceTokenRanges = tokenization.sentenceTokenRanges
        self.wordTokenTotal = tokenization.tokens.filter(\.isWord).count
    }

    func startReciting() async {
        guard phase == .preview, !isStarting else { return }
        isStarting = true
        errorMessage = nil
        defer { isStarting = false }

        do {
            RecitingDebug.resetClock()
            RecitingDebug.log("startReciting: segments=\(segments.count) tokens=\(tokens.count) words=\(wordTokenTotal)")

            let micGranted = await Permissions.requestMicrophone()
            guard micGranted else {
                errorMessage = "未获得麦克风权限，无法开始背诵。"
                RecitingDebug.log("startReciting aborted: microphone permission denied")
                return
            }

            let speechGranted = await Permissions.requestSpeechRecognition()
            guard speechGranted else {
                errorMessage = "未获得语音识别权限，无法开始背诵。"
                RecitingDebug.log("startReciting aborted: speech recognition permission denied")
                return
            }

            await stopReciting(resetToPreview: false)
            phase = .reciting
            recognitionState = .preparing
            revealedTokenCount = 0
            hintEndTokenIndex = nil
            elapsedSeconds = 0
            startDate = nil
            lastPartialText = ""
            lastCommittedWordsText = ""
            recentRecognizedWords = []
            recentPartialWords = []
            lastRecognitionEventAt = nil
            matchedWordCount = 0
            mismatchCount = 0
            skippedWordCount = 0
            advanceAutoTokens()

            let locale = Locale(identifier: "en-US")
            var engine: any LiveSpeechRecognizerEngine = makeRecognizerEngine(locale: locale)
            engineName = engine.displayName
            recognizerEngine = engine

	            let bindCallbacks: (any LiveSpeechRecognizerEngine) -> Void = { [weak self] engine in
	                engine.onWords = { [weak self] words in
	                    let callbackAt = ProcessInfo.processInfo.systemUptime
	                    Task { @MainActor [weak self] in
	                        guard let self else { return }
	                        if RecitingDebug.enabled {
	                            let delay = ProcessInfo.processInfo.systemUptime - callbackAt
	                            if delay > 0.08 {
	                                RecitingDebug.log(String(format: "main delay onWords=%.0fms", delay * 1000))
	                            }
	                        }
	                        self.lastCommittedWordsText = words.joined(separator: " ")
	                        self.lastRecognitionEventAt = Date()
	                        self.appendRecentRecognizedWords(words)
	                        self.recentPartialWords = []
	                        RecitingDebug.log("onWords: \(words)")
	                        self.consumeRecognizedWords(words)
	                    }
	                }
	                engine.onPartialText = { [weak self] text in
	                    let callbackAt = ProcessInfo.processInfo.systemUptime
	                    Task { @MainActor [weak self] in
	                        guard let self else { return }
	                        if RecitingDebug.enabled {
	                            let delay = ProcessInfo.processInfo.systemUptime - callbackAt
	                            if delay > 0.08 {
	                                RecitingDebug.log(String(format: "main delay onPartial=%.0fms", delay * 1000))
	                            }
	                            self.lastPartialText = RecitingDebug.truncate(text, limit: 120)
	                            self.lastRecognitionEventAt = Date()
	                        }
	                        self.updateRecentPartialWords(from: text)
	                    }
	                }
                engine.onError = { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.recognitionState = .error
                        self.errorMessage = error.localizedDescription
                        RecitingDebug.log("engine error: \(RecitingDebug.describe(error))")
                    }
                }
            }

            bindCallbacks(engine)

            do {
                RecitingDebug.log("engine start: \(engine.displayName) locale=\(locale.identifier)")
                try await engine.start()
                recognitionState = .listening
                startDate = Date()
                startTimer()
                RecitingDebug.log("engine started: \(engine.displayName)")
            } catch {
                RecitingDebug.log("engine start failed: \(engine.displayName) err=\(RecitingDebug.describe(error))")
                await engine.stop()

                if #available(iOS 26.0, *), engine is SpeechAnalyzerRecognizerEngine {
                    RecitingDebug.log("fallback to SFSpeechRecognizerEngine")
                    let fallback = SFSpeechRecognizerEngine(locale: locale)
                    engine = fallback
                    engineName = engine.displayName
                    recognizerEngine = engine
                    bindCallbacks(engine)

                    RecitingDebug.log("engine start: \(engine.displayName) locale=\(locale.identifier)")
                    try await engine.start()
                    recognitionState = .listening
                    startDate = Date()
                    startTimer()
                    RecitingDebug.log("engine started: \(engine.displayName)")
                } else {
                    throw error
                }
            }
        } catch {
            recognitionState = .error
            errorMessage = error.localizedDescription
            RecitingDebug.log("startReciting failed: \(RecitingDebug.describe(error))")
            await stopReciting(resetToPreview: true)
        }
    }

    func stopReciting(resetToPreview: Bool) async {
        RecitingDebug.log("stopReciting: resetToPreview=\(resetToPreview)")
        timerTask?.cancel()
        timerTask = nil
        startDate = nil
        elapsedSeconds = 0

        let engine = recognizerEngine
        recognizerEngine = nil
        await engine?.stop()

        if resetToPreview {
            phase = .preview
            recognitionState = .idle
            engineName = ""
            revealedTokenCount = 0
            hintEndTokenIndex = nil
            lastPartialText = ""
            lastCommittedWordsText = ""
            recentRecognizedWords = []
            recentPartialWords = []
            lastRecognitionEventAt = nil
            matchedWordCount = 0
            mismatchCount = 0
            skippedWordCount = 0
        } else if phase != .preview {
            recognitionState = .idle
            recentPartialWords = []
        }
    }

    func cleanup() {
        Task { await stopReciting(resetToPreview: true) }
    }

    func showHint() {
        guard phase != .preview else { return }

        if RecitingDebug.enabled {
            guard hintEndTokenIndex == nil else { return }
            guard let start = nextWordTokenIndex(from: revealedTokenCount) else { return }
            guard let end = sentenceEndTokenIndex(containing: start) else { return }
            guard end > revealedTokenCount else { return }
            hintEndTokenIndex = end
            let hintText = tokens[revealedTokenCount..<min(end, tokens.count)].map(\.text).joined()
            RecitingDebug.log("hint(debug): show sentence up to=\(end) text=\(RecitingDebug.truncate(hintText, limit: 60))")
            return
        }

        guard hintEndTokenIndex == nil else { return }
        guard let start = nextWordTokenIndex(from: revealedTokenCount) else { return }

        var index = start
        var wordCount = 0
        while index < tokens.count, wordCount < 2 {
            if tokens[index].isWord {
                wordCount += 1
            }
            index += 1
        }

        guard index > revealedTokenCount else { return }
        hintEndTokenIndex = index
        let hintText = tokens[revealedTokenCount..<min(index, tokens.count)].map(\.text).joined()
        RecitingDebug.log("hint: show up to=\(index) text=\(RecitingDebug.truncate(hintText, limit: 60))")
    }

    func skipNextWord() {
        guard phase != .preview else { return }
        guard let nextWordIndex = nextWordTokenIndex(from: revealedTokenCount) else { return }

        skippedWordCount += 1
        revealedTokenCount = nextWordIndex + 1
        advanceAutoTokens()

        if let hintEndTokenIndex, revealedTokenCount >= hintEndTokenIndex {
            self.hintEndTokenIndex = nil
            RecitingDebug.log("hint cleared: revealed=\(revealedTokenCount)")
        }

        let skippedText = tokens[nextWordIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        RecitingDebug.log("skip: tokenIndex=\(nextWordIndex) text=\(RecitingDebug.truncate(skippedText, limit: 32)) revealed=\(revealedTokenCount)")
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let startDate else { continue }
                elapsedSeconds = max(0, Int(Date().timeIntervalSince(startDate)))
            }
        }
    }

    private func consumeRecognizedWords(_ words: [String]) {
        guard phase != .preview else { return }
        for word in words {
            guard let nextWordIndex = nextWordTokenIndex(from: revealedTokenCount) else { break }
            let expected = tokens[nextWordIndex].normalizedWord ?? ""
            let spoken = RecitationTokenizer.normalizeWord(word)
            guard !spoken.isEmpty else { continue }

            if spoken == expected {
                matchedWordCount += 1
                if matchedWordCount <= 10 || matchedWordCount % 20 == 0 {
                    RecitingDebug.log("match: \(spoken) tokenIndex=\(nextWordIndex) revealed=\(revealedTokenCount)->\(nextWordIndex + 1)")
                }
                revealedTokenCount = nextWordIndex + 1
                advanceAutoTokens()
                if let hintEndTokenIndex, revealedTokenCount >= hintEndTokenIndex {
                    self.hintEndTokenIndex = nil
                    RecitingDebug.log("hint cleared: revealed=\(revealedTokenCount)")
                }
            } else {
                mismatchCount += 1
                if mismatchCount <= 10 || mismatchCount % 25 == 0 {
                    RecitingDebug.log("mismatch: expected=\(expected) spoken=\(spoken) tokenIndex=\(nextWordIndex)")
                }
            }
        }
    }

    private func nextWordTokenIndex(from tokenCount: Int) -> Int? {
        var idx = max(0, tokenCount)
        while idx < tokens.count {
            if tokens[idx].isWord { return idx }
            idx += 1
        }
        return nil
    }

    private func sentenceEndTokenIndex(containing tokenIndex: Int) -> Int? {
        guard tokenIndex >= 0 else { return nil }
        for end in sentenceEndTokenIndices where tokenIndex < end {
            return end
        }
        return nil
    }

    private func sentenceIndex(containing tokenIndex: Int) -> Int? {
        guard tokenIndex >= 0 else { return nil }
        for (index, range) in sentenceTokenRanges.enumerated() {
            if range.contains(tokenIndex) {
                return index
            }
        }
        return nil
    }

    private func appendRecentRecognizedWords(_ words: [String]) {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }

        recentRecognizedWords.append(contentsOf: cleaned)
        let limit = 6
        if recentRecognizedWords.count > limit {
            recentRecognizedWords = Array(recentRecognizedWords.suffix(limit))
        }
    }

    private func updateRecentPartialWords(from text: String) {
        let cleaned = text
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            if !recentPartialWords.isEmpty {
                recentPartialWords = []
            }
            return
        }
        let limit = 3
        let next = Array(cleaned.suffix(limit))
        if next != recentPartialWords {
            recentPartialWords = next
        }
    }

    private func advanceAutoTokens() {
        while revealedTokenCount < tokens.count, !tokens[revealedTokenCount].isWord {
            revealedTokenCount += 1
        }
    }

    private func makeRecognizerEngine(locale: Locale) -> any LiveSpeechRecognizerEngine {
        if #available(iOS 26.0, *) {
            return SpeechAnalyzerRecognizerEngine(locale: locale)
        }
        return SFSpeechRecognizerEngine(locale: locale)
    }

    private var recognitionStateText: String {
        switch recognitionState {
        case .idle:
            return "idle"
        case .preparing:
            return "preparing"
        case .listening:
            return "listening"
        case .error:
            return "error"
        }
    }
}

enum RecitationTokenizer {
    struct TokenizationResult {
        let transcriptText: String
        let tokens: [RecitationToken]
        let sentenceEndTokenIndices: [Int]
        let sentenceTokenRanges: [Range<Int>]
    }

    static func tokenizeSentences(_ sentences: [String]) -> TokenizationResult {
        let cleaned = sentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let transcriptText = cleaned.joined(separator: "\n\n")

        var resultTokens: [RecitationToken] = []
        resultTokens.reserveCapacity(max(16, transcriptText.count / 3))
        var sentenceEnds: [Int] = []
        sentenceEnds.reserveCapacity(cleaned.count)
        var sentenceRanges: [Range<Int>] = []
        sentenceRanges.reserveCapacity(cleaned.count)

        for (idx, sentence) in cleaned.enumerated() {
            let startIndex = resultTokens.count
            let sentenceTokens = tokenize(sentence)
            resultTokens.append(contentsOf: sentenceTokens)
            let endIndex = resultTokens.count
            sentenceEnds.append(endIndex)
            sentenceRanges.append(startIndex..<endIndex)

            if idx != cleaned.count - 1 {
                resultTokens.append(RecitationToken(text: "\n\n", normalizedWord: nil))
            }
        }

        return TokenizationResult(
            transcriptText: transcriptText,
            tokens: resultTokens,
            sentenceEndTokenIndices: sentenceEnds,
            sentenceTokenRanges: sentenceRanges
        )
    }

    static func tokenize(_ text: String) -> [RecitationToken] {
        guard !text.isEmpty else { return [] }

        var result: [RecitationToken] = []
        result.reserveCapacity(max(16, text.count / 3))

        var currentScalars: [UnicodeScalar] = []
        var currentKind: Kind?

        func flushCurrent() {
            guard let currentKind, !currentScalars.isEmpty else { return }
            let tokenText = String(String.UnicodeScalarView(currentScalars))

            switch currentKind {
            case .word:
                result.append(RecitationToken(text: tokenText, normalizedWord: normalizeWord(tokenText)))
            case .nonWord:
                result.append(RecitationToken(text: tokenText, normalizedWord: nil))
            }

            currentScalars.removeAll(keepingCapacity: true)
        }

        for scalar in text.unicodeScalars {
            let kind: Kind = isWordScalar(scalar) ? .word : .nonWord

            if currentKind == nil {
                currentKind = kind
            } else if currentKind != kind {
                flushCurrent()
                currentKind = kind
            }

            currentScalars.append(scalar)
        }

        flushCurrent()
        return result
    }

    static func normalizeWord(_ word: String) -> String {
        let scalars = word.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func isWordScalar(_ scalar: UnicodeScalar) -> Bool {
        if CharacterSet.alphanumerics.contains(scalar) { return true }
        if scalar == "'" || scalar == "’" || scalar == "-" { return true }
        return false
    }

    private enum Kind: Equatable {
        case word
        case nonWord
    }
}

private enum Permissions {
    static func requestMicrophone() async -> Bool {
        RecitingDebug.log("request microphone permission")
        return await AVAudioApplication.requestRecordPermission()
    }

    static func requestSpeechRecognition() async -> Bool {
        RecitingDebug.log("request speech recognition permission")
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                RecitingDebug.log("speech recognition auth status=\(status.rawValue)")
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
