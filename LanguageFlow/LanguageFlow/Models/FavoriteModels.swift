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
    var titleTranslation: String?
    var audioURL: String
    var language: String = ""
    var timestamp: Int = 0
    var segmentCount: Int
    var duration: Int?
    var createdAt: Date

    init(podcast: Podcast) {
        self.id = podcast.id
        self.title = podcast.title
        self.titleTranslation = podcast.titleTranslation
        self.audioURL = podcast.audioURL
        self.language = podcast.language
        self.timestamp = podcast.timestamp
        self.duration = podcast.duration
        self.segmentCount = podcast.segmentCount
        self.createdAt = Date()
    }
}

extension FavoritePodcast {
    func toPodcast() -> Podcast? {
        return Podcast(
            id: id,
            audioURL: audioURL,
            title: title,
            titleTranslation: titleTranslation,
            timestamp: timestamp,
            language: language,
            segmentsURL: "",
            segmentCount: segmentCount,
            status: Podcast.Status(isFavorited: true, bestScore: nil, customPlaybackRate: nil),
            duration: duration
        )
    }
}
