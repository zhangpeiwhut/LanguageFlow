//
//  AudioWaveLoader.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/13/25.
//

import Foundation
@preconcurrency import AVFoundation
import CoreMedia

nonisolated
enum AudioWaveLoader {
    /// 音频 -> 指定采样率的单声道float32的线性PCM振幅值
    static func loadMono(
        from url: URL,
        sampleRate: Double = 16_000,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil
    ) async throws -> [Float] {
        let range: (start: TimeInterval, end: TimeInterval)?
        if let s = start, let e = end {
            let clampedStart = max(0, s)
            let clampedEnd = max(clampedStart, e)
            guard clampedEnd > clampedStart else { return [] }
            range = (clampedStart, clampedEnd)
        } else {
            range = nil
        }

        do {
            if let range {
                return try loadMonoUsingAVAudioFile(from: url, sampleRate: sampleRate, start: range.start, end: range.end)
            } else {
                return try loadMonoUsingAVAudioFile(from: url, sampleRate: sampleRate, start: nil, end: nil)
            }
        } catch {
            let avAudioFileError = error
            ShadowingDebug.log("loadMono AVAudioFile failed: \(ShadowingDebug.fileSummary(url: url)) err=\(ShadowingDebug.describe(avAudioFileError)), fallback to AVAssetReader")

            do {
                if let range {
                    let startTime = CMTime(seconds: range.start, preferredTimescale: 600)
                    let endTime = CMTime(seconds: range.end, preferredTimescale: 600)
                    let timeRange = CMTimeRangeFromTimeToTime(start: startTime, end: endTime)
                    return try await loadMonoUsingAssetReader(from: url, sampleRate: sampleRate, timeRange: timeRange)
                } else {
                    return try await loadMonoUsingAssetReader(from: url, sampleRate: sampleRate, timeRange: nil)
                }
            } catch {
                let primary = avAudioFileError as NSError
                let secondary = error as NSError
                ShadowingDebug.log("loadMono AVAssetReader failed: \(ShadowingDebug.fileSummary(url: url)) err=\(ShadowingDebug.describe(secondary))")
                throw NSError(
                    domain: "AudioWaveLoader",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "音频解码失败。AVAudioFile: \(primary.domain)(\(primary.code)) \(primary.localizedDescription); AVAssetReader: \(secondary.domain)(\(secondary.code)) \(secondary.localizedDescription)",
                        NSUnderlyingErrorKey: secondary,
                        "AVAudioFileError": primary
                    ]
                )
            }
        }
    }


    private static func loadMonoUsingAVAudioFile(
        from url: URL,
        sampleRate: Double,
        start: TimeInterval? = nil,
        end: TimeInterval? = nil
    ) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat

        // 计算需要读取的 frame 区间
        let inputSR = inputFormat.sampleRate
        let totalFrames = file.length

        let startSeconds = max(0, start ?? 0)
        let endSeconds: TimeInterval = {
            if let end { return max(startSeconds, end) }
            // nil 表示读到文件末尾
            return totalFrames > 0 ? (Double(totalFrames) / inputSR) : startSeconds
        }()

        let startFrame = AVAudioFramePosition(startSeconds * inputSR)
        let endFrame = AVAudioFramePosition(endSeconds * inputSR)

        let clampedStartFrame = max(0, min(startFrame, totalFrames))
        let clampedEndFrame = max(clampedStartFrame, min(endFrame, totalFrames))
        let framesToRead = AVAudioFrameCount(clampedEndFrame - clampedStartFrame)
        guard framesToRead > 0 else { return [] }

        file.framePosition = clampedStartFrame

        ShadowingDebug.log(
            "loadMonoUsingAVAudioFile start: \(ShadowingDebug.fileSummary(url: url)) " +
            "range=\(startSeconds)s...\(endSeconds)s frames=\(framesToRead) " +
            "input sr=\(inputSR) ch=\(inputFormat.channelCount) fmt=\(inputFormat.commonFormat) -> sr=\(sampleRate)"
        )

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create output audio format"]
            )
        }

        // Fast path：已经是目标格式（单声道、float32、目标采样率）
        if inputFormat.sampleRate == outputFormat.sampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32 {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: framesToRead) else {
                throw NSError(
                    domain: "AudioWaveLoader",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"]
                )
            }
            try file.read(into: buffer, frameCount: framesToRead)
            guard let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return [] }
            return Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]
            )
        }

        let inputFrameCapacity: AVAudioFrameCount = min(4_096, framesToRead)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputFrameCapacity) else {
            throw NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"]
            )
        }

        let outputFrameCapacity: AVAudioFrameCount = 4_096
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            throw NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"]
            )
        }

        let expected = Int(Double(framesToRead) * (outputFormat.sampleRate / inputFormat.sampleRate))
        var waveform: [Float] = []
        waveform.reserveCapacity(max(0, expected))

        var framesRemaining = AVAudioFramePosition(framesToRead)

        while true {
            outputBuffer.frameLength = 0

            var error: NSError?
            var readError: Error?
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                do {
                    if framesRemaining <= 0 {
                        outStatus.pointee = .endOfStream
                        return nil
                    }

                    let toRead = min(inputFrameCapacity, AVAudioFrameCount(framesRemaining))
                    try file.read(into: inputBuffer, frameCount: toRead)

                    if inputBuffer.frameLength == 0 {
                        outStatus.pointee = .endOfStream
                        return nil
                    }

                    framesRemaining -= AVAudioFramePosition(inputBuffer.frameLength)
                    outStatus.pointee = .haveData
                    return inputBuffer
                } catch {
                    readError = error
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }

            if let readError { throw readError }
            if let error { throw error }

            switch status {
            case .haveData:
                let frames = Int(outputBuffer.frameLength)
                guard frames > 0, let channelData = outputBuffer.floatChannelData?[0] else { continue }
                waveform.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))

            case .inputRanDry:
                continue

            case .endOfStream:
                let frames = Int(outputBuffer.frameLength)
                if frames > 0, let channelData = outputBuffer.floatChannelData?[0] {
                    waveform.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))
                }
                return waveform

            case .error:
                throw NSError(
                    domain: "AudioWaveLoader",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Audio conversion failed"]
                )

            @unknown default:
                return waveform
            }
        }
    }

    private static func loadMonoUsingAssetReader(
        from url: URL,
        sampleRate: Double,
        timeRange: CMTimeRange?
    ) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No audio track found"]
            )
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            let ns = error as NSError
            throw NSError(
                domain: "AudioWaveLoader",
                code: ns.code,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create AVAssetReader: \(ns.domain)(\(ns.code)) \(ns.localizedDescription)",
                    NSUnderlyingErrorKey: ns
                ]
            )
        }

        if var timeRange {
            // Defensive clamp: segment timestamps may slightly exceed the actual asset duration.
            let duration = try await asset.load(.duration)
            ShadowingDebug.log("loadMonoUsingAssetReader timeRange raw=\(CMTimeGetSeconds(timeRange.start))...\(CMTimeGetSeconds(timeRange.end)) assetDuration=\(duration.isNumeric ? duration.seconds : -1)")
            if duration.isNumeric && duration.isValid && duration.seconds.isFinite {
                let start = max(timeRange.start, .zero)
                let end = min(timeRange.end, duration)
                guard end > start else { return [] }
                timeRange = CMTimeRangeFromTimeToTime(start: start, end: end)
            }
            reader.timeRange = timeRange
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetReader cannot add track output"]
            )
        }
        reader.add(output)

        guard reader.startReading() else {
            throw reader.error ?? NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed to start reading"]
            )
        }

        var waveform: [Float] = []
        while reader.status == .reading {
            let didRead: Bool = autoreleasepool {
                guard let sampleBuffer = output.copyNextSampleBuffer() else {
                    return false
                }
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                    return true
                }

                let length = CMBlockBufferGetDataLength(blockBuffer)
                guard length > 0 else { return true }

                var data = Data(count: length)
                data.withUnsafeMutableBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else { return }
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
                }

                let count = length / MemoryLayout<Float32>.size
                data.withUnsafeBytes { rawBuffer in
                    let floats = rawBuffer.bindMemory(to: Float32.self)
                    waveform.append(contentsOf: floats.prefix(count))
                }
                return true
            }
            if !didRead { break }
        }

        switch reader.status {
        case .completed:
            ShadowingDebug.log("loadMonoUsingAssetReader completed: \(ShadowingDebug.fileSummary(url: url)) samples=\(waveform.count) sr=\(sampleRate)")
            return waveform
        case .failed:
            throw reader.error ?? NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed"]
            )
        case .cancelled:
            throw NSError(
                domain: "AudioWaveLoader",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetReader cancelled"]
            )
        default:
            return waveform
        }
    }

    static func trimSilenceWithInfo(
        _ waveform: [Float],
        sampleRate: Int,
        frameMs: Double = 20,
        hopMs: Double = 10,
        thresholdRatio: Float = 0.06,
        minActiveFrames: Int = 2,
        paddingMs: Double = 40,
        baseThreshold: Float = 0.003
    ) -> (trimmed: [Float], start: Int, end: Int, threshold: Float, noiseEnergy: Float, maxEnergy: Float) {
        guard !waveform.isEmpty else { return ([], 0, -1, baseThreshold, 0, 0) }

        let sr = Double(sampleRate)
        let frame = max(1, Int(sr * frameMs / 1000.0))
        let hop = max(1, Int(sr * hopMs / 1000.0))
        let pad = max(0, Int(sr * paddingMs / 1000.0))
        let needFrames = max(1, minActiveFrames)

        func meanAbs(at start: Int) -> Float {
            let end = min(waveform.count, start + frame)
            if start >= end { return 0 }
            var sum: Float = 0
            var n: Int = 0
            for i in start..<end {
                let x = waveform[i]
                if x.isNaN || x.isInfinite { continue }
                sum += abs(x)
                n += 1
            }
            guard n > 0 else { return 0 }
            return sum / Float(n)
        }

        func estimateNoiseEnergy(energies: [Float], maxEnergy: Float) -> Float {
            guard !energies.isEmpty, maxEnergy > 1e-6 else { return 0 }
            let sorted = energies.sorted()
            let idx = max(0, min(sorted.count - 1, Int(Float(sorted.count - 1) * 0.2)))
            let p20 = sorted[idx]
            if p20 / maxEnergy > 0.7 { return 0 }
            return p20
        }

        // Pass 1: per-frame energy + max
        var maxE: Float = 0
        var energies: [Float] = []
        energies.reserveCapacity(max(1, waveform.count / hop))
        var s = 0
        while s < waveform.count {
            let e = meanAbs(at: s)
            if e > maxE { maxE = e }
            energies.append(e)
            if s + frame >= waveform.count { break }
            s += hop
        }
        let noiseE = estimateNoiseEnergy(energies: energies, maxEnergy: maxE)
        let dynamic = max(0, maxE - noiseE)
        let thrFromNoise: Float = {
            if noiseE > 0, dynamic > 1e-6 {
                return noiseE + dynamic * thresholdRatio
            }
            return maxE * thresholdRatio
        }()
        let thr = max(baseThreshold, thrFromNoise)

        // Pass 2: find start (consecutive active frames)
        var startFrameSample: Int?
        var active = 0
        s = 0
        while s < waveform.count {
            let e = meanAbs(at: s)
            if e >= thr {
                active += 1
                if active >= needFrames {
                    startFrameSample = s - (needFrames - 1) * hop
                    break
                }
            } else {
                active = 0
            }
            if s + frame >= waveform.count { break }
            s += hop
        }

        // Pass 3: find end (from tail, consecutive active frames)
        var endFrameEndSample: Int?
        active = 0
        let lastStart = max(0, waveform.count - frame)
        s = lastStart
        while s >= 0 {
            let e = meanAbs(at: s)
            if e >= thr {
                active += 1
                if active >= needFrames {
                    endFrameEndSample = s + (needFrames - 1) * hop + frame
                    break
                }
            } else {
                active = 0
            }
            if s == 0 { break }
            s = max(0, s - hop)
        }

        guard let start0 = startFrameSample,
              let end0 = endFrameEndSample else {
            return (waveform, 0, waveform.count - 1, thr, noiseE, maxE)
        }

        let start = max(0, start0 - pad)
        let end = min(waveform.count, end0 + pad) - 1
        guard end > start else { return (waveform, 0, waveform.count - 1, thr, noiseE, maxE) }
        return (Array(waveform[start...end]), start, end, thr, noiseE, maxE)
    }
}
