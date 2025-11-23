import SwiftUI

struct PodcastHeroHeader: View {
    let podcast: Podcast
    
    private var totalDurationMinutes: Int {
        guard let lastSegment = podcast.segments.last else { return 0 }
        return Int(lastSegment.end / 60)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(podcast.title ?? "Podcast")
                .font(.headline)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Text("\(totalDurationMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(podcast.segments.count) 句")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
