//
//  FavoriteModels.swift
//  LanguageFlow
//

import Foundation
import SwiftData

@Model
final class FavoriteSegment {
    @Attribute(.unique) var id: String
    var podcastId: String
    var segmentId: Int
    var audioURL: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var translation: String?
    var createdAt: Date
    
    init(
        id: String,
        podcastId: String,
        segmentId: Int,
        audioURL: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        translation: String?
    ) {
        self.id = id
        self.podcastId = podcastId
        self.segmentId = segmentId
        self.audioURL = audioURL
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.translation = translation
        self.createdAt = Date()
    }
    
    static func from(_ segment: Podcast.Segment, podcast: Podcast) -> FavoriteSegment {
        let id = "\(podcast.id)-\(segment.id)"
        return FavoriteSegment(
            id: id,
            podcastId: podcast.id,
            segmentId: segment.id,
            audioURL: podcast.audioURL,
            startTime: segment.start,
            endTime: segment.end,
            text: segment.text,
            translation: segment.translation
        )
    }
    
    func toFavoritePodcastSegment() -> FavoritePodcastSegment {
        FavoritePodcastSegment(
            id: id,
            podcastId: podcastId,
            segmentId: segmentId,
            audioURL: audioURL,
            startTime: startTime,
            endTime: endTime,
            text: text,
            translation: translation
        )
    }
}

@Model
final class FavoritePodcast {
    @Attribute(.unique) var id: String
    var title: String?
    var subtitle: String?
    var audioURL: String
    var createdAt: Date

    init(id: String, title: String?, subtitle: String?, audioURL: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.audioURL = audioURL
        self.createdAt = Date()
    }
}
