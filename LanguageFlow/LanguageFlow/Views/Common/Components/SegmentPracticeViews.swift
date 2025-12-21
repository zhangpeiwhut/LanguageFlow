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
                    onToggleLoop: { store.toggleSegmentLoop(for: segment) },
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
    let onToggleLoop: () -> Void
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
                isFavorited: state.isFavorited,
                isLooping: state.isLooping,
                onToggleLoop: onToggleLoop,
                onFavorite: onFavorite
            )
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? Color(.systemBackground) : Color(.secondarySystemBackground))
                .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 8, x: 0, y: 2)
        }
        .overlay(alignment: .leading) {
            if isActive {
                UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: 14,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(Color.accentColor)
                .frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
    let isFavorited: Bool
    let isLooping: Bool
    let onToggleLoop: () -> Void
    let onFavorite: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Spacer()

            Button(action: onToggleLoop) {
                HStack(spacing: 4) {
                    Image(systemName: "repeat")
                        .font(.system(size: 16, weight: .medium))

                    if isLooping {
                        Text("循环")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
                .foregroundColor(isLooping ? .primary : .secondary)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
                .background {
                    if isLooping {
                        Capsule()
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isLooping)
            }
            .buttonStyle(.plain)

            Button(action: onFavorite) {
                Image(systemName: isFavorited ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isFavorited ? .red : .secondary)
                    .padding(.trailing, 8)
                    .padding(.vertical, 7)
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
