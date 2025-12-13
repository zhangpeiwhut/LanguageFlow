//
//  ShadowingScorer.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/13/25.
//

import Foundation

nonisolated
struct ShadowingScorer: Sendable {
    /// DTW band width as a fraction of max(T, U).
    /// Final band also includes `abs(T-U)` so a valid path always exists.
    var bandRatio: Float = 0.35

    /// Distance→score calibration.
    /// For different speakers, cosine distances often sit around 0.65~0.9 (DTW mean),
    /// so keep the mapping a bit more lenient to avoid "always low" scores.
    /// `dGood` ≈ “very good shadowing” distance (maps close to 100).
    var dGood: Float = 0.71
    var dBad: Float = 1.18

    func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        // a,b 已 L2 normalize，则 cosine similarity = dot(a,b)
        var dot: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i] }
        let clamped = min(1, max(-1, dot))
        return 1 - clamped
    }

    func meanNoDTW(ref: [[Float]], hyp: [[Float]]) -> Float {
        let n = min(ref.count, hyp.count)
        guard n > 0 else { return .infinity }
        var s: Float = 0
        for i in 0..<n { s += cosineDistance(ref[i], hyp[i]) }
        return s / Float(n)
    }

    /// DTW mean path distance with Sakoe-Chiba band
    func meanDTW(ref: [[Float]], hyp: [[Float]]) -> Float {
        let T = ref.count
        let U = hyp.count
        guard T > 0, U > 0 else { return .infinity }

        let minBand = abs(T - U)
        let ratioBand = max(1, Int(Float(max(T, U)) * bandRatio))
        let band = max(minBand, ratioBand)
        let INF: Float = 1e18

        var prev = Array(repeating: INF, count: U + 1)
        var curr = Array(repeating: INF, count: U + 1)
        prev[0] = 0

        var prevLen = Array(repeating: Int.max / 4, count: U + 1)
        var currLen = Array(repeating: Int.max / 4, count: U + 1)
        prevLen[0] = 0

        for i in 1...T {
            for j in 0...U { curr[j] = INF; currLen[j] = Int.max / 4 }

            let jMin = max(1, i - band)
            let jMax = min(U, i + band)

            if jMin > jMax { return .infinity }

            for j in jMin...jMax {
                let d = cosineDistance(ref[i - 1], hyp[j - 1])

                // down, right, diag
                var bestCost = prev[j]
                var bestLen  = prevLen[j]

                if curr[j - 1] < bestCost {
                    bestCost = curr[j - 1]
                    bestLen  = currLen[j - 1]
                }
                if prev[j - 1] < bestCost {
                    bestCost = prev[j - 1]
                    bestLen  = prevLen[j - 1]
                }

                curr[j] = bestCost + d
                currLen[j] = bestLen + 1
            }

            prev = curr
            prevLen = currLen
        }

        let total = prev[U]
        let steps = prevLen[U]
        guard steps > 0, total < INF/2 else { return .infinity }
        return total / Float(steps)
    }

    /// 线性映射到 0~100（你现在的标定）
    func score(fromMeanDist d: Float) -> Float {
        guard d.isFinite else { return 0 }
        let s = 100 * (dBad - d) / (dBad - dGood)
        return max(0, min(100, s))
    }
}
