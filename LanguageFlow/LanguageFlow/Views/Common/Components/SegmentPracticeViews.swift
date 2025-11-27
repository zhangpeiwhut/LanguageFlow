import SwiftUI
import Observation
import Foundation

struct SegmentListView: View {
    @Bindable var store: PodcastLearningStore
    var onLookup: (String) -> Void

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(store.segments.enumerated()), id: \.element.id) { index, segment in
                SegmentPracticeCard(
                    segment: segment,
                    segmentNumber: index + 1,
                    totalSegments: max(store.segments.count, 1),
                    state: Binding(
                        get: { store.segmentStates[segment.id] ?? SegmentPracticeState() },
                        set: { store.segmentStates[segment.id] = $0 }
                    ),
                    isActive: store.currentSegmentID == segment.id,
                    areTranslationsHidden: store.areTranslationsHidden,
                    onPlay: { store.togglePlay(for: segment) },
                    onFavorite: { store.toggleFavorite(for: segment) },
                    onRateChange: { rate in store.updatePlaybackRate(rate, for: segment) },
                    onAttemptChange: { text in store.updateAttempt(text, for: segment) },
                    onToggleTranslation: { store.toggleTranslation(for: segment) },
                    onLookup: onLookup
                )
                .id(segment.id)
                .animation(.easeInOut(duration: 0.25), value: store.currentSegmentID == segment.id)
            }
        }
    }
}

private struct SegmentPracticeCard: View {
    let segment: Podcast.Segment
    let segmentNumber: Int
    let totalSegments: Int
    @Binding var state: SegmentPracticeState
    let isActive: Bool
    let areTranslationsHidden: Bool
    let onPlay: () -> Void
    let onFavorite: () -> Void
    let onRateChange: (Double) -> Void
    let onAttemptChange: (String) -> Void
    let onToggleTranslation: () -> Void
    let onLookup: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            numberTag()
            
            InteractiveWordText(
                text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                onLookup: onLookup
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if let translation = segment.translation {
                Text(translation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .blur(radius: areTranslationsHidden && !state.isTranslationVisible ? 5 : 0)
                    .animation(.easeInOut(duration: 0.2), value: areTranslationsHidden && !state.isTranslationVisible)
                    .contentShape(Rectangle())
                    .allowsHitTesting(areTranslationsHidden)
                    .onTapGesture {
                        if areTranslationsHidden {
                            onToggleTranslation()
                        }
                    }
            }
            
            SegmentPracticeControls(
                isPlaying: state.isPlaying,
                isFavorited: state.isFavorited,
                playbackRate: state.playbackRate,
                onFavorite: onFavorite,
                onRateChange: onRateChange
            )
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay()
        }
    }
    
    @ViewBuilder
    private func numberTag() -> some View {
        Text("\(segmentNumber)/\(totalSegments)")
            .font(.caption.bold())
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemFill))
            )
    }
}

private struct SegmentPracticeControls: View {
    let isPlaying: Bool
    let isFavorited: Bool
    let playbackRate: Double
    let onFavorite: () -> Void
    let onRateChange: (Double) -> Void
    
    private let rateOptions: [Double] = [0.75, 1.0, 1.25]

    private func nextRate() -> Double {
        guard let currentIndex = rateOptions.firstIndex(of: playbackRate) else {
            return rateOptions[0]
        }
        let nextIndex = (currentIndex + 1) % rateOptions.count
        return rateOptions[nextIndex]
    }

    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            
            Button {
                onRateChange(nextRate())
            } label: {
                Text("\(playbackRate, specifier: "%.2fx")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onFavorite) {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.body)
                    .foregroundColor(isFavorited ? .pink : .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PlaybackRateSlider: View {
    let rate: Double
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("倍速 \(rate, specifier: "%.2fx")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Slider(value: Binding(
                get: { rate },
                set: { newValue in
                    onChange(newValue)
                }
            ), in: 0.5...2, step: 0.05)
        }
    }
}

private struct ScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score) 分")
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(scoreColor.opacity(0.15))
            .foregroundColor(scoreColor)
            .clipShape(Capsule())
    }

    private var scoreColor: Color {
        switch score {
        case 85...:
            return .green
        case 60..<85:
            return .orange
        default:
            return .red
        }
    }
}
