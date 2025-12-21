//
//  PodcastCardView.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/16/25.
//

import SwiftUI

struct PodcastCardView: View {
    let podcast: PodcastSummary
    let showTranslation: Bool
    let durationText: String
    let segmentText: String
    let onTap: () -> Void
    let isCompleted: Bool

    @State private var shakeTrigger = 0
    @Environment(AuthManager.self) private var authManager

    private var originalTitle: String {
        let base = (podcast.title ?? podcast.titleTranslation ?? "无标题").removingTrailingDateSuffix()
        return stripTrailingPeriod(base)
    }

    private var translatedTitle: String? {
        guard let translation = podcast.titleTranslation, !translation.isEmpty else { return nil }
        let cleaned = translation.removingTrailingDateSuffix()
        return stripTrailingPeriod(cleaned)
    }

    private func stripTrailingPeriod(_ text: String) -> String {
        var result = text
        while let last = result.last, last == "." || last == "。" {
            result.removeLast()
        }
        return result
    }

    private var isLocked: Bool {
        !(podcast.isFree || authManager.isVIP)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(originalTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let translatedTitle {
                            Text(translatedTitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .blur(radius: showTranslation ? 0 : 5)
                                .animation(.easeInOut(duration: 0.2), value: showTranslation)
                        }
                    }

                    Spacer()

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .phaseAnimator(
                                ShakePhase.allCases,
                                trigger: shakeTrigger
                            ) { view, phase in
                                view.rotationEffect(phase.angle, anchor: .top)
                            } animation: { phase in
                                switch phase {
                                case .idle: .easeOut(duration: 0.1)
                                case .left: .easeInOut(duration: 0.08)
                                case .right: .easeInOut(duration: 0.08)
                                case .left2: .easeInOut(duration: 0.08)
                                case .right2: .easeInOut(duration: 0.08)
                                case .end: .easeOut(duration: 0.1)
                                }
                            }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                Color.white,
                                isCompleted ? Color.green : Color(.quaternaryLabel)
                            )
                    }
                }

                Text("\(durationText) • \(segmentText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
    }

    private func handleTap() {
        if isLocked {
            shakeTrigger += 1
        }
        onTap()
    }
}

// MARK: - Shake Animation Phase
enum ShakePhase: CaseIterable {
    case idle
    case left
    case right
    case left2
    case right2
    case end

    var angle: Angle {
        switch self {
        case .idle: .zero
        case .left: .degrees(-20)
        case .right: .degrees(20)
        case .left2: .degrees(-15)
        case .right2: .degrees(15)
        case .end: .zero
        }
    }
}
