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
    private let segmentCache = SegmentCacheManager.shared

    private init() {}

    func favoritePodcast(_ podcast: Podcast, segments: [Podcast.Segment], context: ModelContext) async throws {
        let descriptor = FetchDescriptor<FavoritePodcast>(
            predicate: #Predicate { $0.id == podcast.id }
        )
        if let _ = try? context.fetch(descriptor).first {
            return
        } else {
            let favoritePodcast = FavoritePodcast(podcast: podcast)
            context.insert(favoritePodcast)
        }
        try context.save()
        try await audioCache.ensureAudioCached(forPodcastId: podcast.id, remoteURL: podcast.audioURL)
        try await segmentCache.ensureSegmentsCached(forPodcastId: podcast.id, segments: segments)
    }

    func unfavoritePodcast(_ podcastId: String, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<FavoritePodcast>(
            predicate: #Predicate { $0.id == podcastId }
        )
        if let favoritePodcast = try? context.fetch(descriptor).first {
            context.delete(favoritePodcast)
            try context.save()
            let remainingSegments = try context.fetch(
                FetchDescriptor<FavoriteSegment>(
                    predicate: #Predicate { $0.podcastId == podcastId }
                )
            )
            if remainingSegments.isEmpty {
                await audioCache.deleteCachedAudio(forPodcastId: podcastId)
                await segmentCache.deleteCachedSegments(forPodcastId: podcastId)
            }
        }
    }

    func isPodcastFavorited(_ podcastId: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<FavoritePodcast>(
            predicate: #Predicate { $0.id == podcastId }
        )
        return (try? context.fetch(descriptor).first) != nil
    }

    func favoriteSegment(
        _ segment: Podcast.Segment,
        from podcast: Podcast,
        context: ModelContext
    ) async throws {
        let segmentId = "\(podcast.id)-\(segment.id)"
        let descriptor = FetchDescriptor<FavoriteSegment>(
            predicate: #Predicate { $0.id == segmentId }
        )
        if let _ = try? context.fetch(descriptor).first {
            return
        } else {
            let favoriteSegment = FavoriteSegment.from(segment, podcast: podcast)
            context.insert(favoriteSegment)
        }
        try context.save()
        try await audioCache.ensureAudioCached(forPodcastId: podcast.id, remoteURL: podcast.audioURL)
    }

    func unfavoriteSegment(_ segmentId: String, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<FavoriteSegment>(
            predicate: #Predicate { $0.id == segmentId }
        )
        if let favoriteSegment = try context.fetch(descriptor).first {
            let podcastId = favoriteSegment.podcastId
            context.delete(favoriteSegment)
            try context.save()
            
            let remainingSegments = try context.fetch(
                FetchDescriptor<FavoriteSegment>(
                    predicate: #Predicate { $0.podcastId == podcastId }
                )
            )
            let hasPodcastFavorite = isPodcastFavorited(podcastId, context: context)
            if remainingSegments.isEmpty && !hasPodcastFavorite {
                await audioCache.deleteCachedAudio(forPodcastId: podcastId)
            }
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

    @discardableResult
    func ensureLocalAudio(for segment: FavoritePodcastSegment) async throws -> URL {
        try await audioCache.ensureAudioCached(forPodcastId: segment.podcastId, remoteURL: segment.audioURL)
    }

    @discardableResult
    func ensureLocalAudio(for podcast: Podcast) async throws -> URL {
        try await audioCache.ensureAudioCached(forPodcastId: podcast.id, remoteURL: podcast.audioURL)
    }

    func cachedFavoritePodcast(_ podcastId: String, context: ModelContext) -> FavoritePodcast? {
        let descriptor = FetchDescriptor<FavoritePodcast>(
            predicate: #Predicate { $0.id == podcastId }
        )
        return try? context.fetch(descriptor).first
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
