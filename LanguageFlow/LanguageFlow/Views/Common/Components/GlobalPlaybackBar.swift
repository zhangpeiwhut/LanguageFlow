import SwiftUI

struct GlobalPlaybackBar: View {
    let title: String
    let titleTranslation: String
    let isPlaying: Bool
    let playbackRate: Double
    let progressBinding: Binding<Double>
    let currentTime: Double
    let duration: Double
    let onTogglePlay: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onChangeRate: (Double) -> Void
    let onSeekEditingChanged: (Bool) -> Void
    let isFavorited: Bool
    let onToggleFavorite: () -> Void

    init(
        title: String,
        titleTranslation: String,
        isPlaying: Bool,
        playbackRate: Double,
        progressBinding: Binding<Double>,
        currentTime: Double,
        duration: Double,
        onTogglePlay: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onChangeRate: @escaping (Double) -> Void,
        onSeekEditingChanged: @escaping (Bool) -> Void,
        isFavorited: Bool,
        onToggleFavorite: @escaping () -> Void,
        onShadowingTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.titleTranslation = titleTranslation
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.progressBinding = progressBinding
        self.currentTime = currentTime
        self.duration = duration
        self.onTogglePlay = onTogglePlay
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onChangeRate = onChangeRate
        self.onSeekEditingChanged = onSeekEditingChanged
        self.isFavorited = isFavorited
        self.onToggleFavorite = onToggleFavorite
    }

    private let rateOptions: [Double] = [0.75, 1.0, 1.5, 2.0]

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: progressBinding, in: 0...1, onEditingChanged: onSeekEditingChanged)
                .tint(Color.accentColor)
            
            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            HStack {
                favoriteButton
                Spacer()
                previousButton
                Spacer()
                playButton
                Spacer()
                nextButton
                Spacer()
                rateButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private var playButton: some View {
        Button(action: onTogglePlay) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Color.primary, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
    
    
    private var previousButton: some View {
        Button(action: onPrevious) {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button(action: onNext) {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
    
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.system(size: 24))
                .foregroundStyle(isFavorited ? .red : .primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
    
    private var rateButton: some View {
        Button(action: {
            if let currentIndex = rateOptions.firstIndex(of: playbackRate) {
                let nextIndex = (currentIndex + 1) % rateOptions.count
                onChangeRate(rateOptions[nextIndex])
            } else {
                onChangeRate(rateOptions[0])
            }
        }) {
            Text("\(playbackRate, specifier: "%.2fx")")
                .font(.system(size: 20))
                .foregroundStyle(.primary)
                .frame(minWidth: 50, minHeight: 40)
                .fixedSize()
            }
        .buttonStyle(.plain)
    }
}
