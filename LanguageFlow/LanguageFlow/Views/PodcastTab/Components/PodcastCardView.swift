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
    let onToggleCompletion: () -> Void

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

                    HStack(spacing: 8) {
                        if podcast.isFree || authManager.isVIP {
                            Button {
                                onToggleCompletion()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(
                                        Color.white,
                                        isCompleted ? Color.main : Color(white: 0.85)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .keyframeAnimator(
                                    initialValue: ShakeValues(),
                                    trigger: shakeTrigger,
                                    content: { view, values in
                                        view
                                            .rotationEffect(values.angle, anchor: .top)
                                    }, keyframes: { _ in
                                        KeyframeTrack(\.angle) {
                                            LinearKeyframe(.zero, duration: 0)
                                            LinearKeyframe(.degrees(15), duration: 0.1)
                                            LinearKeyframe(.degrees(-15), duration: 0.2)
                                            LinearKeyframe(.zero, duration: 0.1)
                                        }
                                    }
                                )
                        }
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
        if podcast.isFree || authManager.isVIP {
            onTap()
        } else {
            shakeTrigger += 1
        }
    }
}

// MARK: - Shake Animation Values
struct ShakeValues {
    var angle: Angle = .zero
}
