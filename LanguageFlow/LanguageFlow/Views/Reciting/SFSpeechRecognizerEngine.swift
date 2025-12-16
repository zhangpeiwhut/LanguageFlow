//
//  SFSpeechRecognizerEngine.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/16/25.
//
import Foundation
import Speech

final class SFSpeechRecognizerEngine: NSObject, LiveSpeechRecognizerEngine {
    let displayName: String = "SFSpeechRecognizer"
    var onWords: (@Sendable ([String]) -> Void)?
    var onPartialText: (@Sendable (String) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let locale: Locale
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let stateQueue = DispatchQueue(label: "Reciting.SFSpeechRecognizerEngine.state")
    private var committedSegmentCount: Int = 0
    private var latestSegments: [SFTranscriptionSegment] = []
    private var silenceCommitWorkItem: DispatchWorkItem?
    private var lastPartial: String = ""
    private var didLogFirstAudioBuffer: Bool = false
    private var shouldLogFirstAudioBuffer: Bool = false
    private var resultCounter: Int = 0
    private var firstTapUptime: TimeInterval?
    private var didLogFirstResultLatency: Bool = false
    private var didCaptureFirstTapUptime: Bool = false

    init(locale: Locale) {
        self.locale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    func start() async throws {
        await stop()

        guard let recognizer else {
            throw SpeechEngineError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw SpeechEngineError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        do {
            try session.setPreferredSampleRate(16_000)
        } catch {
            RecitingDebug.log("SFSpeech preferred sample rate failed: \(RecitingDebug.describe(error))")
        }
        do {
            try session.setPreferredInputNumberOfChannels(1)
        } catch {
            RecitingDebug.log("SFSpeech preferred input channels failed: \(RecitingDebug.describe(error))")
        }
        do {
            try session.setPreferredIOBufferDuration(0.01)
        } catch {
            RecitingDebug.log("SFSpeech preferred IO buffer duration failed: \(RecitingDebug.describe(error))")
        }
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        RecitingDebug.log("SFSpeech audio session: \(RecitingDebug.audioSessionSummary(session))")
        if !session.isInputAvailable || session.inputNumberOfChannels <= 0 {
            throw SpeechEngineError.noMicrophoneInput
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        committedSegmentCount = 0
        latestSegments = []
        silenceCommitWorkItem?.cancel()
        silenceCommitWorkItem = nil
        didLogFirstAudioBuffer = false
        shouldLogFirstAudioBuffer = RecitingDebug.enabled
        resultCounter = 0
        stateQueue.sync {
            firstTapUptime = nil
            didLogFirstResultLatency = false
        }
        didCaptureFirstTapUptime = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let error {
                RecitingDebug.log("SFSpeech callback error: \(RecitingDebug.describe(error))")
                self.onError?(error)
                return
            }
            guard let result else { return }
            let receivedAt = ProcessInfo.processInfo.systemUptime
            self.stateQueue.async { [weak self] in
                self?._handle(result: result, receivedAt: receivedAt)
            }
        }

        let inputNode = audioEngine.inputNode
        let tapFormat = RecitingAudioTap.chooseInputTapFormat(inputNode: inputNode, session: session, tag: "SFSpeech")
        guard let tapFormat else {
            throw SpeechEngineError.invalidInputAudioFormat
        }
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            if !self.didCaptureFirstTapUptime {
                self.didCaptureFirstTapUptime = true
                let now = ProcessInfo.processInfo.systemUptime
                self.stateQueue.async { [weak self] in
                    self?.firstTapUptime = now
                }
            }
            if self.shouldLogFirstAudioBuffer, !self.didLogFirstAudioBuffer {
                self.didLogFirstAudioBuffer = true
                RecitingDebug.log("SFSpeech first tap buffer: frames=\(buffer.frameLength) format=\(RecitingDebug.audioFormatSummary(buffer.format))")
            }
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        RecitingDebug.log("SFSpeech audioEngine started")
    }

    func stop() async {
        RecitingDebug.log("SFSpeech stop")
        silenceCommitWorkItem?.cancel()
        silenceCommitWorkItem = nil

        stateQueue.sync {
            committedSegmentCount = 0
            latestSegments = []
            lastPartial = ""
            didLogFirstAudioBuffer = false
            shouldLogFirstAudioBuffer = false
            resultCounter = 0
            firstTapUptime = nil
            didLogFirstResultLatency = false
        }
        didCaptureFirstTapUptime = false

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func _handle(result: SFSpeechRecognitionResult, receivedAt: TimeInterval) {
        let now = ProcessInfo.processInfo.systemUptime
        let queueDelay = now - receivedAt
        if queueDelay > 0.08 {
            RecitingDebug.log(String(format: "SFSpeech stateQueue delay=%.0fms", queueDelay * 1000))
        }
        if !didLogFirstResultLatency {
            didLogFirstResultLatency = true
            if let firstTapUptime {
                RecitingDebug.log(String(format: "SFSpeech first result latency=%.3fs", now - firstTapUptime))
            }
        }

        let partial = result.bestTranscription.formattedString
        if partial != lastPartial {
            lastPartial = partial
            onPartialText?(partial)
        }

        resultCounter += 1
        if result.isFinal || resultCounter <= 8 {
            RecitingDebug.log("SFSpeech result: #\(resultCounter) final=\(result.isFinal) segments=\(result.bestTranscription.segments.count) text=\(RecitingDebug.truncate(partial, limit: 64))")
        }

        latestSegments = result.bestTranscription.segments
        let commitUpTo = result.isFinal ? latestSegments.count : max(0, latestSegments.count - 1)
        commitSegments(upTo: commitUpTo)

        silenceCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.commitSegments(upTo: self.latestSegments.count)
        }
        silenceCommitWorkItem = workItem
        stateQueue.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func commitSegments(upTo count: Int) {
        let safeCount = max(0, min(count, latestSegments.count))
        guard safeCount > committedSegmentCount else { return }

        let newSegments = latestSegments[committedSegmentCount..<safeCount]
        committedSegmentCount = safeCount

        let newWords: [String] = newSegments.flatMap { segment in
            segment.substring.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        }
        if !newWords.isEmpty {
            RecitingDebug.log("SFSpeech commitWords: \(newWords)")
            onWords?(newWords)
        }
    }

    private enum SpeechEngineError: LocalizedError {
        case recognizerUnavailable
        case noMicrophoneInput
        case invalidInputAudioFormat

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "语音识别暂不可用，请稍后重试。"
            case .noMicrophoneInput:
                return "当前设备没有可用的麦克风输入。"
            case .invalidInputAudioFormat:
                return "麦克风音频格式异常，无法启动识别。"
            }
        }
    }
}
