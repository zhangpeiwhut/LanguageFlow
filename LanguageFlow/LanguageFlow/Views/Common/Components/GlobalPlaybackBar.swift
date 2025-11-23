import SwiftUI

struct GlobalPlaybackBar: View {
    let title: String
    let subtitle: String
    let isPlaying: Bool
    let playbackRate: Double
    let progressBinding: Binding<Double>
    let currentTime: Double
    let duration: Double
    let onTogglePlay: () -> Void
    let onChangeRate: (Double) -> Void
    let onSeekEditingChanged: (Bool) -> Void
    let isFavorited: Bool
    let onToggleFavorite: () -> Void
    let isLooping: Bool
    let areTranslationsHidden: Bool
    let onToggleLoopMode: () -> Void
    let onToggleTranslations: () -> Void

    private let rateOptions: [Double] = [0.75, 1.0, 1.25]
    
    private var progress: Double {
        progressBinding.wrappedValue
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                loopButton
                Spacer()
                translationButton
                Spacer()
                playButton
                Spacer()
                favoriteButton
                Spacer()
                rateButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
    
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorited ? "heart.fill" : "heart")
                .font(.system(size: 24))
                .foregroundStyle(isFavorited ? .red : .primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
    
    private var loopButton: some View {
        Button(action: onToggleLoopMode) {
            Image(systemName: isLooping ? "point.forward.to.point.capsulepath.fill" : "point.forward.to.point.capsulepath")
                .font(.system(size: 24))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }
    
    private var translationButton: some View {
        Button(action: onToggleTranslations) {
            Image(systemName: areTranslationsHidden ? "lightbulb.slash" : "lightbulb")
                .font(.system(size: 24))
                .foregroundStyle(.primary)
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
