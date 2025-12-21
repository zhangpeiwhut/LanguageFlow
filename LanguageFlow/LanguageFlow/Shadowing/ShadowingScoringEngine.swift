//
//  ShadowingScoringEngine.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/14/25.
//

import Foundation

actor ShadowingScoringEngine {
    private let localAudioURL: URL

    private let embedder: FrillTFLiteEmbedder
    private let scorer = ShadowingScorer()

    init(localAudioURL: URL) throws {
        self.localAudioURL = localAudioURL
        self.embedder = try FrillTFLiteEmbedder()
    }

    func score(
        referenceStart: TimeInterval,
        referenceEnd: TimeInterval,
        userAudioURL: URL
    ) async throws -> ShadowingResult {
        ShadowingDebug.log("score start: ref=\(ShadowingDebug.fileSummary(url: localAudioURL)) start=\(referenceStart) end=\(referenceEnd) user=\(ShadowingDebug.fileSummary(url: userAudioURL))")
        let refSlice = try await AudioWaveLoader.loadMono(
            from: localAudioURL,
            sampleRate: Double(FrillTFLiteEmbedder.sampleRate),
            start: referenceStart,
            end: referenceEnd
        )
        ShadowingDebug.log("refSlice \(summarizeWaveform(refSlice, sampleRate: Double(FrillTFLiteEmbedder.sampleRate)))")
        let minSamples = Int(Double(FrillTFLiteEmbedder.sampleRate) * 0.25)
        let refTrimInfo = AudioWaveLoader.trimSilenceWithInfo(refSlice, sampleRate: FrillTFLiteEmbedder.sampleRate)
        let refTrimmed = refTrimInfo.trimmed
        if ShadowingDebug.enabled {
            let sr = Double(FrillTFLiteEmbedder.sampleRate)
            let head = Double(refTrimInfo.start) / sr
            let tail = Double(max(0, refSlice.count - 1 - refTrimInfo.end)) / sr
            ShadowingDebug.log("trim ref: head=\(String(format: "%.3f", head))s tail=\(String(format: "%.3f", tail))s thr=\(String(format: "%.4f", refTrimInfo.threshold)) noiseE=\(String(format: "%.4f", refTrimInfo.noiseEnergy)) maxE=\(String(format: "%.4f", refTrimInfo.maxEnergy))")
        }
        ShadowingDebug.log("refTrimmed \(summarizeWaveform(refTrimmed, sampleRate: Double(FrillTFLiteEmbedder.sampleRate)))")
        guard refTrimmed.count >= minSamples else {
            throw NSError(
                domain: "ShadowingScoringEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "参考音频片段太短，无法打分"]
            )
        }

        let refNormalized = normalizeForEmbeddingWithInfo(refTrimmed)
        if ShadowingDebug.enabled {
            ShadowingDebug.log("normalize ref: rms=\(String(format: "%.4f", refNormalized.rms)) peak=\(String(format: "%.4f", refNormalized.peak)) gain=\(String(format: "%.2f", refNormalized.gain))")
        }
        let refAudio = SentenceAudio(waveform16k: refNormalized.waveform)
        let userWave = try await AudioWaveLoader.loadMono(
            from: userAudioURL,
            sampleRate: Double(FrillTFLiteEmbedder.sampleRate)
        )
        ShadowingDebug.log("userWave \(summarizeWaveform(userWave, sampleRate: Double(FrillTFLiteEmbedder.sampleRate)))")
        let userTrimInfo = AudioWaveLoader.trimSilenceWithInfo(userWave, sampleRate: FrillTFLiteEmbedder.sampleRate)
        let userTrimmed = userTrimInfo.trimmed
        if ShadowingDebug.enabled {
            let sr = Double(FrillTFLiteEmbedder.sampleRate)
            let head = Double(userTrimInfo.start) / sr
            let tail = Double(max(0, userWave.count - 1 - userTrimInfo.end)) / sr
            ShadowingDebug.log("trim user: head=\(String(format: "%.3f", head))s tail=\(String(format: "%.3f", tail))s thr=\(String(format: "%.4f", userTrimInfo.threshold)) noiseE=\(String(format: "%.4f", userTrimInfo.noiseEnergy)) maxE=\(String(format: "%.4f", userTrimInfo.maxEnergy))")
        }
        ShadowingDebug.log("userTrimmed \(summarizeWaveform(userTrimmed, sampleRate: Double(FrillTFLiteEmbedder.sampleRate)))")
        let userMaxAbs = waveformMaxAbs(userTrimmed)
        if userMaxAbs < 0.02 {
            throw NSError(
                domain: "ShadowingScoringEngine",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "没有录到清晰的人声，请再试一次"]
            )
        }
        guard userTrimmed.count >= minSamples else {
            throw NSError(
                domain: "ShadowingScoringEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "录音时间太短，请再试一次"]
            )
        }

        if !refTrimmed.isEmpty {
            let ratio = Double(userTrimmed.count) / Double(refTrimmed.count)
            ShadowingDebug.log("duration ratio user/ref=\(String(format: "%.2f", ratio)) (user=\(String(format: "%.2f", Double(userTrimmed.count) / Double(FrillTFLiteEmbedder.sampleRate)))s ref=\(String(format: "%.2f", Double(refTrimmed.count) / Double(FrillTFLiteEmbedder.sampleRate)))s)")
        }
        let userNormalized = normalizeForEmbeddingWithInfo(userTrimmed)
        if ShadowingDebug.enabled {
            ShadowingDebug.log("normalize user: rms=\(String(format: "%.4f", userNormalized.rms)) peak=\(String(format: "%.4f", userNormalized.peak)) gain=\(String(format: "%.2f", userNormalized.gain))")
        }
        let userAudio = SentenceAudio(waveform16k: userNormalized.waveform)

        let comparison = try compare(reference: refAudio, user: userAudio)
        let waveformComparison = makeWaveformComparisonPreview(
            referenceWaveform: refTrimmed,
            userWaveform: userTrimmed,
            sampleRate: FrillTFLiteEmbedder.sampleRate
        )

        let durationFactor: Float = {
            guard !refTrimmed.isEmpty else { return 1 }
            let ratio = Double(userTrimmed.count) / Double(refTrimmed.count)
            let low = 0.60
            let high = 1.60
            if ratio < low {
                return Float(max(0, ratio / low))
            }
            if ratio > high {
                return Float(max(0, high / ratio))
            }
            return 1
        }()
        let finalScore = min(100, max(0, comparison.score * durationFactor))
        if ShadowingDebug.enabled {
            ShadowingDebug.log("score adjust: durationFactor=\(String(format: "%.2f", durationFactor)) score=\(String(format: "%.2f", comparison.score)) -> \(String(format: "%.2f", finalScore))")
        }

        let result = ShadowingResult(
            acousticScore: finalScore,
            meanDistance: comparison.meanDistance,
            refFrames: comparison.refFrames,
            userFrames: comparison.userFrames,
            waveformComparison: waveformComparison
        )
        ShadowingDebug.log("score done: score=\(result.acousticScore) meanDist=\(result.meanDistance) refFrames=\(result.refFrames) userFrames=\(result.userFrames)")
        return result
    }

    private func compare(reference: SentenceAudio, user: SentenceAudio) throws -> (score: Float, meanDistance: Float, refFrames: Int, userFrames: Int) {
        let refSeqRaw = try embedder.embedSequence(waveform: reference.waveform16k)
        let userSeqRaw = try embedder.embedSequence(waveform: user.waveform16k)

        // Mean-center per-utterance to reduce speaker/recording condition bias, then L2 normalize again.
        let refSeqCentered = meanCenterAndNormalize(refSeqRaw)
        let userSeqCentered = meanCenterAndNormalize(userSeqRaw)

        // Coarse alignment: estimate an initial lag so "start offset" doesn't overly hurt DTW.
        let maxLag = min(12, max(0, min(refSeqCentered.count, userSeqCentered.count) / 2))
        let align = bestLagByCosine(ref: refSeqCentered, user: userSeqCentered, maxLag: maxLag)
        let aligned = applyLag(align.lagFrames, ref: refSeqCentered, user: userSeqCentered)

        // Mix DTW (tempo-tolerant) + no-DTW (stricter) to reduce false positives
        // like "random speech still gets decent score".
        let dDTW = scorer.meanDTW(ref: aligned.ref, hyp: aligned.user)
        let dNoDTW = scorer.meanNoDTW(ref: aligned.ref, hyp: aligned.user)
        let dBase = 0.8 * dDTW + 0.2 * dNoDTW

        // Similarity-based penalty (for "speaking other content") should be conservative,
        // otherwise short segments (few frames) will have very noisy sim and wildly fluctuating scores.
        let sim = align.similarity
        let minFrames = min(aligned.ref.count, aligned.user.count)
        let penaltyScale = min(1, Float(minFrames) / 20)
        let simGate: Float = 0.14
        let simPenaltyMax: Float = 0.18

        let simPenalty: Float
        if !sim.isFinite {
            simPenalty = simPenaltyMax * penaltyScale
        } else if sim >= simGate {
            simPenalty = 0
        } else {
            let t = max(0, min(1, (simGate - sim) / simGate))
            simPenalty = (t * t) * simPenaltyMax * penaltyScale
        }

        let d = dBase + simPenalty

        if ShadowingDebug.enabled {
            let refDur = Double(reference.waveform16k.count) / Double(FrillTFLiteEmbedder.sampleRate)
            let refSecPerFrame = refDur / Double(max(1, refSeqCentered.count))
            let approxOffset = Double(align.lagFrames) * refSecPerFrame
            ShadowingDebug.log("align lagFrames=\(align.lagFrames) approxOffset=\(String(format: "%.3f", approxOffset))s (pos=user leads) sim=\(String(format: "%.3f", align.similarity)) maxLag=\(maxLag)")
            ShadowingDebug.log("dist dtw=\(dDTW) noDTW=\(dNoDTW) base=\(dBase) sim=\(String(format: "%.3f", sim)) gate=\(String(format: "%.2f", simGate)) scale=\(String(format: "%.2f", penaltyScale)) penalty=\(String(format: "%.3f", simPenalty)) final=\(d)")
        }

        let score = scorer.score(fromMeanDist: d)
        return (score: score, meanDistance: d, refFrames: aligned.ref.count, userFrames: aligned.user.count)
    }

    private func bestLagByCosine(
        ref: [[Float]],
        user: [[Float]],
        maxLag: Int
    ) -> (lagFrames: Int, similarity: Float) {
        let T = ref.count
        let U = user.count
        guard T > 0, U > 0 else { return (0, 0) }
        let maxLagClamped = max(0, min(maxLag, min(T, U) - 1))
        guard maxLagClamped > 0 else { return (0, averageCosineSimilarity(ref: ref, user: user, lag: 0)) }

        var bestLag = 0
        var bestSim = averageCosineSimilarity(ref: ref, user: user, lag: 0)
        for lag in (-maxLagClamped)...maxLagClamped where lag != 0 {
            let s = averageCosineSimilarity(ref: ref, user: user, lag: lag)
            if s > bestSim {
                bestSim = s
                bestLag = lag
            }
        }
        return (bestLag, bestSim)
    }

    private func applyLag(
        _ lag: Int,
        ref: [[Float]],
        user: [[Float]]
    ) -> (ref: [[Float]], user: [[Float]]) {
        guard lag != 0 else { return (ref, user) }
        if lag > 0 {
            if lag >= user.count { return (ref, user) }
            return (ref, Array(user.dropFirst(lag)))
        } else {
            let k = -lag
            if k >= ref.count { return (ref, user) }
            return (Array(ref.dropFirst(k)), user)
        }
    }

    private func averageCosineSimilarity(ref: [[Float]], user: [[Float]], lag: Int) -> Float {
        let T = ref.count
        let U = user.count
        guard T > 0, U > 0 else { return 0 }

        var refStart = 0
        var userStart = 0
        if lag > 0 {
            userStart = lag
        } else if lag < 0 {
            refStart = -lag
        }
        let n = min(T - refStart, U - userStart)
        guard n > 0 else { return -1 }

        var sum: Float = 0
        for i in 0..<n {
            sum += dot(ref[refStart + i], user[userStart + i])
        }
        return sum / Float(n)
    }

    private func dot(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var s: Float = 0
        for i in 0..<n { s += a[i] * b[i] }
        return s
    }

    private func meanCenterAndNormalize(_ seq: [[Float]]) -> [[Float]] {
        guard let first = seq.first else { return [] }
        let dim = first.count
        guard dim > 0 else { return seq }
        guard seq.count > 1 else { return seq }

        var mean = [Float](repeating: 0, count: dim)
        for frame in seq {
            guard frame.count == dim else { return seq }
            for i in 0..<dim { mean[i] += frame[i] }
        }
        let inv = 1 / Float(seq.count)
        for i in 0..<dim { mean[i] *= inv }

        var out: [[Float]] = []
        out.reserveCapacity(seq.count)
        for frame in seq {
            var centered = [Float](repeating: 0, count: dim)
            var sum: Float = 0
            for i in 0..<dim {
                let v = frame[i] - mean[i]
                centered[i] = v
                sum += v * v
            }
            let norm = sqrt(sum) + 1e-8
            for i in 0..<dim { centered[i] /= norm }
            out.append(centered)
        }
        return out
    }

    private func summarizeWaveform(_ waveform: [Float], sampleRate: Double) -> String {
        guard !waveform.isEmpty else { return "samples=0" }
        var maxAbs: Float = 0
        var nanCount = 0
        var sumSq: Double = 0
        var n: Int = 0
        for x in waveform {
            if x.isNaN || x.isInfinite {
                nanCount += 1
                continue
            }
            let ax = abs(x)
            if ax > maxAbs { maxAbs = ax }
            sumSq += Double(x) * Double(x)
            n += 1
        }
        let seconds = Double(waveform.count) / sampleRate
        let rms = n > 0 ? sqrt(sumSq / Double(n)) : 0
        if nanCount > 0 {
            return "samples=\(waveform.count) sec=\(String(format: "%.3f", seconds)) maxAbs=\(String(format: "%.4f", maxAbs)) rms=\(String(format: "%.4f", rms)) nanOrInf=\(nanCount)"
        }
        return "samples=\(waveform.count) sec=\(String(format: "%.3f", seconds)) maxAbs=\(String(format: "%.4f", maxAbs)) rms=\(String(format: "%.4f", rms))"
    }

    private func waveformMaxAbs(_ waveform: [Float]) -> Float {
        var maxAbs: Float = 0
        for x in waveform {
            if x.isNaN || x.isInfinite { continue }
            let ax = abs(x)
            if ax > maxAbs { maxAbs = ax }
        }
        return maxAbs
    }

    private func normalizeForEmbeddingWithInfo(
        _ waveform: [Float],
        targetRMS: Float = 0.1,
        maxGain: Float = 12
    ) -> (waveform: [Float], rms: Float, peak: Float, gain: Float) {
        guard !waveform.isEmpty else { return ([], 0, 0, 1) }
        var sumSq: Double = 0
        var n = 0
        var peak: Float = 0
        for x in waveform {
            if x.isNaN || x.isInfinite { continue }
            sumSq += Double(x) * Double(x)
            n += 1
            let ax = abs(x)
            if ax > peak { peak = ax }
        }
        let rms = n > 0 ? Float(sqrt(sumSq / Double(n))) : 0
        guard rms > 1e-6, peak > 1e-6 else { return (waveform, rms, peak, 1) }

        var gain = targetRMS / rms
        gain = min(maxGain, max(1 / maxGain, gain))
        gain = min(gain, 0.98 / peak)

        if abs(gain - 1) < 0.01 {
            return (waveform, rms, peak, 1)
        }

        var out: [Float] = []
        out.reserveCapacity(waveform.count)
        for x in waveform {
            if x.isNaN || x.isInfinite {
                out.append(0)
                continue
            }
            let y = x * gain
            out.append(min(1, max(-1, y)))
        }
        return (out, rms, peak, gain)
    }

    private func estimateNoiseEnergy(energies: [Float], maxEnergy: Float) -> Float {
        guard !energies.isEmpty, maxEnergy > 1e-6 else { return 0 }
        // Use a low percentile as a proxy for background/noise floor; ignore if audio is mostly active.
        let sorted = energies.sorted()
        let idx = max(0, min(sorted.count - 1, Int(Float(sorted.count - 1) * 0.2)))
        let p20 = sorted[idx]
        if p20 / maxEnergy > 0.7 { return 0 }
        return p20
    }

    private func makeWaveformComparisonPreview(
        referenceWaveform: [Float],
        userWaveform: [Float],
        sampleRate: Int,
        bins: Int = 240
    ) -> ShadowingWaveformComparison {
        let refBins = downsampleMinMax(referenceWaveform, bins: bins)
        let userBins = downsampleMinMax(userWaveform, bins: bins)
        let denom = max(1e-6, max(refBins.maxAbs, userBins.maxAbs))

        let refPreview = ShadowingWaveformPreview(
            mins: refBins.mins.map { $0 / denom },
            maxs: refBins.maxs.map { $0 / denom },
            durationSeconds: Float(Double(referenceWaveform.count) / Double(sampleRate))
        )
        let userPreview = ShadowingWaveformPreview(
            mins: userBins.mins.map { $0 / denom },
            maxs: userBins.maxs.map { $0 / denom },
            durationSeconds: Float(Double(userWaveform.count) / Double(sampleRate))
        )

        ShadowingDebug.log(
            "waveform preview: bins=\(min(refPreview.mins.count, refPreview.maxs.count)) normMaxAbs=\(String(format: "%.4f", denom)) ref=\(String(format: "%.2f", Double(refPreview.durationSeconds)))s user=\(String(format: "%.2f", Double(userPreview.durationSeconds)))s"
        )

        return ShadowingWaveformComparison(reference: refPreview, user: userPreview)
    }

    private func downsampleMinMax(_ waveform: [Float], bins: Int) -> (mins: [Float], maxs: [Float], maxAbs: Float) {
        guard !waveform.isEmpty else { return ([], [], 0) }
        let binCount = max(1, bins)
        var mins: [Float] = []
        var maxs: [Float] = []
        mins.reserveCapacity(binCount)
        maxs.reserveCapacity(binCount)

        var globalMaxAbs: Float = 0
        let total = waveform.count

        for i in 0..<binCount {
            let start = Int(Double(i) * Double(total) / Double(binCount))
            let rawEnd = Int(Double(i + 1) * Double(total) / Double(binCount))
            let end = min(total, max(start + 1, rawEnd))

            var mn = Float.greatestFiniteMagnitude
            var mx = -Float.greatestFiniteMagnitude

            if start < end {
                for j in start..<end {
                    let x = waveform[j]
                    if x.isNaN || x.isInfinite { continue }
                    if x < mn { mn = x }
                    if x > mx { mx = x }
                }
            }

            if mn == Float.greatestFiniteMagnitude || mx == -Float.greatestFiniteMagnitude {
                mn = 0
                mx = 0
            }

            mins.append(mn)
            maxs.append(mx)

            let absMax = max(abs(mn), abs(mx))
            if absMax > globalMaxAbs { globalMaxAbs = absMax }
        }

        return (mins: mins, maxs: maxs, maxAbs: globalMaxAbs)
    }
}
