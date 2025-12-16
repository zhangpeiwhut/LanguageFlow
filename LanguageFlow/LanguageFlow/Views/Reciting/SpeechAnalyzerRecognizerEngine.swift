//
//  SpeechAnalyzerRecognizerEngine.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/16/25.
//
import Foundation
import AVFAudio
import Speech

@available(iOS 26.0, *)
final class SpeechAnalyzerRecognizerEngine: LiveSpeechRecognizerEngine {
    let displayName: String = "SpeechAnalyzer"
    var onWords: (@Sendable ([String]) -> Void)?
    var onPartialText: (@Sendable (String) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var recognizerTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private let converter = BufferConverter()
    private let stateQueue = DispatchQueue(label: "Reciting.SpeechAnalyzerRecognizerEngine.state")
    private var currentWords: [String] = []
    private var emittedWords: [String] = []
    private var silenceCommitWorkItem: DispatchWorkItem?
    private var lastPartial: String = ""
    private var didReserveLocale: Bool = false
    private var resultCounter: Int = 0
    private var didLogFirstAudioBuffer: Bool = false
    private var shouldLogFirstAudioBuffer: Bool = false
    private var firstTapUptime: TimeInterval?
    private var didLogFirstResultLatency: Bool = false
    private var didCaptureFirstTapUptime: Bool = false

    init(locale: Locale) {
        self.locale = locale
    }

    func start() async throws {
        await stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        RecitingDebug.log("SpeechAnalyzer audio session: \(RecitingDebug.audioSessionSummary(session))")
        if !session.isInputAvailable || session.inputNumberOfChannels <= 0 {
            throw SpeechAnalyzerError.noMicrophoneInput
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        let statusBefore = await AssetInventory.status(forModules: [transcriber])
        RecitingDebug.log("SpeechAnalyzer asset status(before): \(statusBefore)")

        try await ensureModel(transcriber: transcriber, locale: locale)
        do {
            let didReserve = try await AssetInventory.reserve(locale: locale)
            didReserveLocale = didReserve
            RecitingDebug.log("SpeechAnalyzer reserved locale=\(locale.identifier(.bcp47)) didReserve=\(didReserve)")
            let reservedLocales = await AssetInventory.reservedLocales
            let reservedDesc = reservedLocales.map { $0.identifier(.bcp47) }.joined(separator: ",")
            RecitingDebug.log("SpeechAnalyzer reservedLocales=[\(reservedDesc)]")
        } catch {
            RecitingDebug.log("SpeechAnalyzer reserve locale failed: \(RecitingDebug.describe(error))")
            throw error
        }

        let statusAfter = await AssetInventory.status(forModules: [transcriber])
        RecitingDebug.log("SpeechAnalyzer asset status(after): \(statusAfter)")

        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: options)
        self.analyzer = analyzer

        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        RecitingDebug.log("SpeechAnalyzer analyzerFormat: \(RecitingDebug.audioFormatSummary(analyzerFormat))")
        guard let analyzerFormat else {
            throw SpeechAnalyzerError.failedToSetupRecognitionStream
        }
        guard analyzerFormat.sampleRate.isFinite, analyzerFormat.sampleRate > 0, analyzerFormat.channelCount > 0 else {
            throw SpeechAnalyzerError.invalidAnalyzerAudioFormat
        }

        RecitingDebug.log("SpeechAnalyzer prepareToAnalyze start")
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        RecitingDebug.log("SpeechAnalyzer prepareToAnalyze done")

        let stream = AsyncStream<AnalyzerInput> { continuation in
            self.inputContinuation = continuation
        }

        currentWords = []
        emittedWords = []
        resultCounter = 0
        didLogFirstAudioBuffer = false
        shouldLogFirstAudioBuffer = RecitingDebug.enabled
        stateQueue.sync {
            firstTapUptime = nil
            didLogFirstResultLatency = false
        }
        didCaptureFirstTapUptime = false
        silenceCommitWorkItem?.cancel()
        silenceCommitWorkItem = nil
        lastPartial = ""

        recognizerTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let receivedAt = ProcessInfo.processInfo.systemUptime
                    let text = String(result.text.characters)
                    self.stateQueue.async { [weak self] in
                        self?._handle(text: text, isFinal: result.isFinal, receivedAt: receivedAt)
                    }
                }
            } catch {
                RecitingDebug.log("SpeechAnalyzer results error: \(RecitingDebug.describe(error))")
                onError?(error)
            }
        }

        try await analyzer.start(inputSequence: stream)

        try setupAudioEngineTap()
        audioEngine.prepare()
        try audioEngine.start()
        RecitingDebug.log("SpeechAnalyzer audioEngine started")
    }

    func stop() async {
        RecitingDebug.log("SpeechAnalyzer stop")
        silenceCommitWorkItem?.cancel()
        silenceCommitWorkItem = nil

        stateQueue.sync {
            currentWords = []
            emittedWords = []
            resultCounter = 0
            didLogFirstAudioBuffer = false
            shouldLogFirstAudioBuffer = false
            lastPartial = ""
            firstTapUptime = nil
            didLogFirstResultLatency = false
            didCaptureFirstTapUptime = false
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognizerTask?.cancel()
        recognizerTask = nil

        inputContinuation?.finish()
        inputContinuation = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        transcriber = nil

        analyzerFormat = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if didReserveLocale {
            let released = await AssetInventory.release(reservedLocale: locale)
            RecitingDebug.log("SpeechAnalyzer released locale=\(locale.identifier(.bcp47)) released=\(released)")
            didReserveLocale = false
        }
    }

    private func setupAudioEngineTap() throws {
        guard let inputContinuation, let analyzerFormat else {
            throw SpeechAnalyzerError.failedToSetupRecognitionStream
        }

        let session = AVAudioSession.sharedInstance()
        let inputNode = audioEngine.inputNode
        let tapFormat = RecitingAudioTap.chooseInputTapFormat(inputNode: inputNode, session: session, tag: "SpeechAnalyzer")
        guard let tapFormat else {
            throw SpeechAnalyzerError.invalidInputAudioFormat
        }
        RecitingDebug.log("SpeechAnalyzer tap format: \(RecitingDebug.audioFormatSummary(tapFormat)) -> \(RecitingDebug.audioFormatSummary(analyzerFormat))")
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if !self.didCaptureFirstTapUptime {
                self.didCaptureFirstTapUptime = true
                let now = ProcessInfo.processInfo.systemUptime
                self.stateQueue.async { [weak self] in
                    self?.firstTapUptime = now
                }
            }
            do {
                if self.shouldLogFirstAudioBuffer, !self.didLogFirstAudioBuffer {
                    self.didLogFirstAudioBuffer = true
                    RecitingDebug.log("SpeechAnalyzer first tap buffer: frames=\(buffer.frameLength) format=\(RecitingDebug.audioFormatSummary(buffer.format))")
                }
                let converted = try self.converter.convertBuffer(buffer, to: analyzerFormat)
                inputContinuation.yield(AnalyzerInput(buffer: converted))
            } catch {
                RecitingDebug.log("SpeechAnalyzer convert error: \(RecitingDebug.describe(error))")
                self.onError?(error)
            }
        }
    }

    private func _handle(text: String, isFinal: Bool, receivedAt: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        let queueDelay = now - receivedAt
        if queueDelay > 0.08 {
            RecitingDebug.log(String(format: "SpeechAnalyzer stateQueue delay=%.0fms", queueDelay * 1000))
        }
        if !didLogFirstResultLatency {
            didLogFirstResultLatency = true
            if let firstTapUptime {
                RecitingDebug.log(String(format: "SpeechAnalyzer first result latency=%.3fs", now - firstTapUptime))
            }
        }

        if text != lastPartial {
            lastPartial = text
            onPartialText?(text)
        }

        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        currentWords = words
        resultCounter += 1
        if isFinal || resultCounter <= 8 {
            RecitingDebug.log("SpeechAnalyzer result: #\(resultCounter) final=\(isFinal) words=\(words.count) text=\(RecitingDebug.truncate(text, limit: 64))")
        }

        let commonPrefix = Self.commonPrefixCount(lhs: emittedWords, rhs: currentWords)
        if commonPrefix < emittedWords.count {
            RecitingDebug.log("SpeechAnalyzer rewind: emitted=\(emittedWords.count)->\(commonPrefix)")
            emittedWords = Array(emittedWords.prefix(commonPrefix))
        }

        let emitUpTo = isFinal ? currentWords.count : max(0, currentWords.count - 1)
        emitWords(upTo: emitUpTo, reason: isFinal ? "final" : "partial")

        silenceCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.emitWords(upTo: self.currentWords.count, reason: "silence")
        }
        silenceCommitWorkItem = workItem
        stateQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)

        if isFinal {
            silenceCommitWorkItem?.cancel()
            silenceCommitWorkItem = nil
            currentWords = []
            emittedWords = []
        }
    }

    private func emitWords(upTo count: Int, reason: String) {
        let safeCount = max(0, min(count, currentWords.count))
        guard safeCount > emittedWords.count else { return }
        let newWords = Array(currentWords[emittedWords.count..<safeCount])
        emittedWords.append(contentsOf: newWords)
        guard !newWords.isEmpty else { return }
        RecitingDebug.log("SpeechAnalyzer commitWords(\(reason)): \(newWords)")
        onWords?(newWords)
    }

    private static func commonPrefixCount(lhs: [String], rhs: [String]) -> Int {
        let limit = min(lhs.count, rhs.count)
        guard limit > 0 else { return 0 }
        var idx = 0
        while idx < limit {
            let left = RecitationTokenizer.normalizeWord(lhs[idx])
            let right = RecitationTokenizer.normalizeWord(rhs[idx])
            if !left.isEmpty || !right.isEmpty {
                if left != right { break }
            } else if lhs[idx] != rhs[idx] {
                break
            }
            idx += 1
        }
        return idx
    }

    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        let supportedLocales = await SpeechTranscriber.supportedLocales
        guard supportedLocales.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) else {
            throw SpeechAnalyzerError.localeNotSupported
        }

        let installedLocales = await Set(SpeechTranscriber.installedLocales)
        if installedLocales.map({ $0.identifier(.bcp47) }).contains(locale.identifier(.bcp47)) {
            return
        }

        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            RecitingDebug.log("SpeechAnalyzer model download start: locale=\(locale.identifier(.bcp47))")
            try await downloader.downloadAndInstall()
            RecitingDebug.log("SpeechAnalyzer model download done: locale=\(locale.identifier(.bcp47))")
        }
    }

    private enum SpeechAnalyzerError: LocalizedError {
        case failedToSetupRecognitionStream
        case invalidAnalyzerAudioFormat
        case noMicrophoneInput
        case invalidInputAudioFormat
        case localeNotSupported

        var errorDescription: String? {
            switch self {
            case .failedToSetupRecognitionStream:
                return "语音识别初始化失败，请稍后重试。"
            case .invalidAnalyzerAudioFormat:
                return "语音识别音频格式异常，已中止启动。"
            case .noMicrophoneInput:
                return "当前设备没有可用的麦克风输入。"
            case .invalidInputAudioFormat:
                return "麦克风音频格式异常，无法启动识别。"
            case .localeNotSupported:
                return "当前系统语言暂不支持 SpeechAnalyzer。"
            }
        }
    }

    private final class BufferConverter {
        enum Error: Swift.Error {
            case failedToCreateConverter
            case failedToCreateConversionBuffer
            case conversionFailed(NSError?)
        }

        private var converter: AVAudioConverter?

        func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
            let inputFormat = buffer.format
            guard inputFormat.sampleRate.isFinite, inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
                throw Error.failedToCreateConverter
            }
            guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
                throw Error.failedToCreateConverter
            }
            guard inputFormat != format else {
                return buffer
            }

            if converter == nil || converter?.outputFormat != format {
                converter = AVAudioConverter(from: inputFormat, to: format)
                converter?.primeMethod = .none
            }

            guard let converter else {
                throw Error.failedToCreateConverter
            }

            let sampleRateRatio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
            let scaledInputFrameLength = Double(buffer.frameLength) * sampleRateRatio
            let frameCapacity = AVAudioFrameCount(scaledInputFrameLength.rounded(.up))
            guard let conversionBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: frameCapacity) else {
                throw Error.failedToCreateConversionBuffer
            }

            var nsError: NSError?
            var bufferProcessed = false

            let status = converter.convert(to: conversionBuffer, error: &nsError) { _, inputStatusPointer in
                defer { bufferProcessed = true }
                inputStatusPointer.pointee = bufferProcessed ? .noDataNow : .haveData
                return bufferProcessed ? nil : buffer
            }

            guard status != .error else {
                throw Error.conversionFailed(nsError)
            }

            return conversionBuffer
        }
    }
}
