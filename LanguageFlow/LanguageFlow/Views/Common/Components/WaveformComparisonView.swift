//
//  WaveformComparisonView.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/14/25.
//

import SwiftUI
import Charts

struct WaveformComparisonView: View {
    let comparison: ShadowingWaveformComparison

    private struct WaveformBin: Identifiable, Sendable {
        let id: Int
        let min: Double
        let max: Double
    }

    private var refCount: Int { min(comparison.reference.mins.count, comparison.reference.maxs.count) }
    private var userCount: Int { min(comparison.user.mins.count, comparison.user.maxs.count) }
    private var xCount: Int { max(refCount, userCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            legendRow
            chartCard
        }
    }

    private var legendRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 7, height: 7)
                Text("原音(\(formatSeconds(comparison.reference.durationSeconds)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                Text("录音(\(formatSeconds(comparison.user.durationSeconds)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("波形直方图")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var chartCard: some View {
        overlayChart
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var overlayChart: some View {
        Chart {
            midlineMark
            referenceBars
            userBars
        }
        .chartXScale(domain: 0...max(0, xCount - 1))
        .chartYScale(domain: -1...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 84)
    }

    @ChartContentBuilder
    private var midlineMark: some ChartContent {
        RuleMark(y: .value("mid", 0))
            .foregroundStyle(.secondary.opacity(0.25))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    @ChartContentBuilder
    private var referenceBars: some ChartContent {
        ForEach(referenceBarBins) { b in
            RuleMark(
                x: .value("bin", b.id),
                yStart: .value("min", b.min),
                yEnd: .value("max", b.max)
            )
            .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
            .foregroundStyle(Color.blue.opacity(0.30))
        }
    }

    @ChartContentBuilder
    private var userBars: some ChartContent {
        ForEach(userBarBins) { b in
            RuleMark(
                x: .value("bin", b.id),
                yStart: .value("min", b.min),
                yEnd: .value("max", b.max)
            )
            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .foregroundStyle(Color.green.opacity(0.55))
        }
    }

    private var referenceBarBins: [WaveformBin] {
        (0..<refCount).map { i in
            WaveformBin(
                id: i,
                min: Double(comparison.reference.mins[i]),
                max: Double(comparison.reference.maxs[i])
            )
        }
    }

    private var userBarBins: [WaveformBin] {
        (0..<userCount).map { i in
            WaveformBin(
                id: i,
                min: Double(comparison.user.mins[i]),
                max: Double(comparison.user.maxs[i])
            )
        }
    }

    private func formatSeconds(_ seconds: Float) -> String {
        "\(String(format: "%.2f", Double(seconds)))s"
    }
}
