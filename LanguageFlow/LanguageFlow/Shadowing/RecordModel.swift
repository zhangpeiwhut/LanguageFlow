//
//  RecordModel.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/13/25.
//

import Foundation

/// ref/user音频输入
struct SentenceAudio: Sendable {
    let waveform16k: [Float]   // 16k mono float32
}

struct ShadowingWaveformPreview: Sendable, Equatable {
    /// Downsampled per-bin min values, normalized to [-1, 1].
    let mins: [Float]
    /// Downsampled per-bin max values, normalized to [-1, 1].
    let maxs: [Float]
    /// Duration of the (trimmed) waveform in seconds.
    let durationSeconds: Float
}

struct ShadowingWaveformComparison: Sendable, Equatable {
    let reference: ShadowingWaveformPreview
    let user: ShadowingWaveformPreview
}

/// 比对结果
struct ShadowingResult: Sendable {
    let acousticScore: Float   // 0–100
    let meanDistance: Float
    let refFrames: Int
    let userFrames: Int
    let waveformComparison: ShadowingWaveformComparison
}
