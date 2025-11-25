//
//  SegmentCacheManager.swift
//  LanguageFlow
//

import Foundation

final actor SegmentCacheManager {
    static let shared = SegmentCacheManager()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsDirectory
            .appendingPathComponent("Favorites", isDirectory: true)
            .appendingPathComponent("Segments", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachedSegments(forPodcastId podcastId: String) -> [Podcast.Segment]? {
        let destination = makeDestinationURL(forPodcastId: podcastId)
        guard fileManager.fileExists(atPath: destination.path),
              let data = try? Data(contentsOf: destination) else {
            return nil
        }
        return try? decoder.decode([Podcast.Segment].self, from: data)
    }

    @discardableResult
    func cacheSegments(_ segments: [Podcast.Segment], forPodcastId podcastId: String) throws -> URL {
        let destination = makeDestinationURL(forPodcastId: podcastId)
        let data = try encoder.encode(segments)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    @discardableResult
    func ensureSegmentsCached(forPodcastId podcastId: String, segments: [Podcast.Segment]) throws -> [Podcast.Segment] {
        if let cached = cachedSegments(forPodcastId: podcastId) {
            return cached
        }
        guard !segments.isEmpty else {
            throw SegmentCacheError.emptySegments
        }
        try cacheSegments(segments, forPodcastId: podcastId)
        return segments
    }

    func deleteCachedSegments(forPodcastId podcastId: String) {
        let destination = makeDestinationURL(forPodcastId: podcastId)
        try? fileManager.removeItem(at: destination)
    }

    private func makeDestinationURL(forPodcastId podcastId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(podcastId).json")
    }
}

enum SegmentCacheError: LocalizedError {
    case emptySegments

    var errorDescription: String? {
        switch self {
        case .emptySegments:
            return "片段数据为空，请稍后重试"
        }
    }
}
