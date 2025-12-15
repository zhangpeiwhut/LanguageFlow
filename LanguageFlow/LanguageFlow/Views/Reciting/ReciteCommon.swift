//
//  ReciteCommon.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/16/25.
//

import Foundation
import AVFAudio

protocol LiveSpeechRecognizerEngine: AnyObject {
    var displayName: String { get }
    var onWords: (@Sendable ([String]) -> Void)? { get set }
    var onPartialText: (@Sendable (String) -> Void)? { get set }
    var onError: (@Sendable (Error) -> Void)? { get set }

    func start() async throws
    func stop() async
}

struct RecitationToken: Equatable {
    let text: String
    let normalizedWord: String?

    var isWord: Bool {
        normalizedWord != nil
    }
}

enum RecitingAudioTap {
    static func chooseInputTapFormat(
        inputNode: AVAudioInputNode,
        session: AVAudioSession,
        tag: String
    ) -> AVAudioFormat? {
        let outputFormat = inputNode.outputFormat(forBus: 0)
        let inputFormat = inputNode.inputFormat(forBus: 0)

        RecitingDebug.log("\(tag) inputNode outputFormat: \(RecitingDebug.audioFormatSummary(outputFormat))")
        RecitingDebug.log("\(tag) inputNode inputFormat: \(RecitingDebug.audioFormatSummary(inputFormat))")

        if isValid(outputFormat) {
            return outputFormat
        }
        if isValid(inputFormat) {
            return inputFormat
        }

        let sessionRate = session.sampleRate
        let sessionChannels = session.inputNumberOfChannels
        if sessionRate.isFinite, sessionRate > 0, sessionChannels > 0,
           let format = AVAudioFormat(standardFormatWithSampleRate: sessionRate, channels: AVAudioChannelCount(sessionChannels)),
           isValid(format) {
            RecitingDebug.log("\(tag) created session format: \(RecitingDebug.audioFormatSummary(format))")
            return format
        }

        RecitingDebug.log("\(tag) invalid tap formats; sessionSr=\(String(format: "%.0f", sessionRate))Hz sessionCh=\(sessionChannels) inputAvailable=\(session.isInputAvailable)")
        return nil
    }

    private static func isValid(_ format: AVAudioFormat?) -> Bool {
        guard let format else { return false }
        return format.sampleRate.isFinite && format.sampleRate > 0 && format.channelCount > 0
    }
}

nonisolated
enum RecitingDebug {
    private static let uptimeBase: TimeInterval = ProcessInfo.processInfo.systemUptime

    static var enabled: Bool {
        #if DEBUG
        return DebugConfig.recitingDebugEnabled
        #else
        return false
        #endif
    }

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - uptimeBase
        print(String(format: "[Reciting +%.3fs] %@", elapsed, message()))
    }

    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var parts: [String] = ["\(nsError.domain)(\(nsError.code))"]

        let message = nsError.localizedDescription
        if !message.isEmpty {
            parts.append(message)
        }
        if let reason = nsError.localizedFailureReason, !reason.isEmpty, reason != message {
            parts.append(reason)
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying=\(underlying.domain)(\(underlying.code)) \(underlying.localizedDescription)")
        }
        return parts.joined(separator: " ")
    }

    static func truncate(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    static func audioFormatSummary(_ format: AVAudioFormat?) -> String {
        guard let format else { return "nil" }
        let rate = String(format: "%.0f", format.sampleRate)
        return "sr=\(rate)Hz ch=\(format.channelCount)"
    }

    static func audioSessionSummary(_ session: AVAudioSession) -> String {
        let routeOut = session.currentRoute.outputs.map { "\($0.portType.rawValue)(\($0.portName))" }.joined(separator: ",")
        let routeIn = session.currentRoute.inputs.map { "\($0.portType.rawValue)(\($0.portName))" }.joined(separator: ",")
        let rate = String(format: "%.0f", session.sampleRate)
        let io = String(format: "%.4f", session.ioBufferDuration)
        return "cat=\(session.category.rawValue) mode=\(session.mode.rawValue) sr=\(rate)Hz io=\(io)s out=[\(routeOut)] in=[\(routeIn)]"
    }
}
