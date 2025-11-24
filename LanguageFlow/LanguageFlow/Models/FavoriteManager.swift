//
//  FavoriteManager.swift
//  LanguageFlow
//
//

import Foundation
import SwiftData

class FavoriteManager {
    static let shared = FavoriteManager()

    private let audioCache = AudioCacheManager.shared

    private init() {}

    func favoritePodcast(_ podcast: Podcast, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<FavoritePodcast>(
            predicate: #Predicate { $0.id == podcast.id }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.title = podcast.title
            existing.subtitle = podcast.subtitle
            existing.audioURL = podcast.audioURL
        } else {
            let favoritePodcast = FavoritePodcast(
                id: podcast.id,
                title: podcast.title,
                subtitle: podcast.subtitle,
                audioURL: podcast.audioURL
            )
            context.insert(favoritePodcast)
        }
        try context.save()

        Task.detached { [audioCache] in
            try? await audioCache.ensureAudioCached(forPodcastId: podcast.id, audioURL: podcast.audioURL)
        }
    }

    func unfavoritePodcast(_ podcastId: String, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<FavoritePodcast>(
            predicate: #Predicate { $0.id == podcastId }
        )
        if let favoritePodcast = try? context.fetch(descriptor).first {
            context.delete(favoritePodcast)
            try context.save()
        }
    }

    func isPodcastFavorited(_ podcastId: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<FavoritePodcast>(
            predicate: #Predicate { $0.id == podcastId }
        )
        return (try? context.fetch(descriptor).first) != nil
    }

    func favoriteSegment(_ segment: Podcast.Segment, from podcast: Podcast, context: ModelContext) async throws {
        let segmentId = "\(podcast.id)-\(segment.id)"
        let descriptor = FetchDescriptor<FavoriteSegment>(
            predicate: #Predicate { $0.id == segmentId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.text = segment.text
            existing.translation = segment.translation
            existing.startTime = segment.start
            existing.endTime = segment.end
            existing.audioURL = podcast.audioURL
        } else {
            let favoriteSegment = FavoriteSegment.from(segment, podcast: podcast)
            context.insert(favoriteSegment)
        }
        try context.save()

        Task.detached { [audioCache] in
            try? await audioCache.ensureAudioCached(forPodcastId: podcast.id, audioURL: podcast.audioURL)
        }
    }

    func unfavoriteSegment(_ segmentId: String, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<FavoriteSegment>(
            predicate: #Predicate { $0.id == segmentId }
        )
        if let favoriteSegment = try? context.fetch(descriptor).first {
            context.delete(favoriteSegment)
            try context.save()
        }
    }
    
    func isSegmentFavorited(_ segmentId: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<FavoriteSegment>(
            predicate: #Predicate { $0.id == segmentId }
        )
        return (try? context.fetch(descriptor).first) != nil
    }
    
    func getAllFavoriteSegments(context: ModelContext) throws -> [FavoritePodcastSegment] {
        let descriptor = FetchDescriptor<FavoriteSegment>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let favoriteSegments = try context.fetch(descriptor)
        return favoriteSegments.map { $0.toFavoritePodcastSegment() }
    }

    func cachedAudioURL(for segment: FavoritePodcastSegment) -> URL? {
        audioCache.cachedAudioURL(forPodcastId: segment.podcastId, audioURL: segment.audioURL)
    }

    @discardableResult
    func ensureLocalAudio(for segment: FavoritePodcastSegment) async throws -> URL {
        try await audioCache.ensureAudioCached(forPodcastId: segment.podcastId, audioURL: segment.audioURL)
    }

    @discardableResult
    func ensureLocalAudio(for podcast: Podcast) async throws -> URL {
        try await audioCache.ensureAudioCached(forPodcastId: podcast.id, audioURL: podcast.audioURL)
    }
}

enum FavoriteError: LocalizedError {
    case invalidAudioURL
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidAudioURL:
            return "无效的音频URL"
        case .downloadFailed:
            return "音频下载失败，请稍后重试"
        }
    }
}
