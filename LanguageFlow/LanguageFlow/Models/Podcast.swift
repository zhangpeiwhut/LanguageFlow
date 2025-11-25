//
//  Podcast.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 11/18/25.
//

import Foundation

struct Channel: Codable, Identifiable {
    let company: String
    let channel: String
    var id: String {
        "\(company)-\(channel)"
    }
}

struct PodcastSummary: Codable, Identifiable {
    let id: String
    let title: String?
    let titleTranslation: String?
    let segmentCount: Int?
    let duration: Int?
}

struct Podcast: Codable, Identifiable {
    let id: String
    let audioURL: String
    let title: String?
    let subtitle: String?
    let timestamp: Int
    let language: String
    let segmentsURL: String
    let segmentCount: Int
    let status: Status?
    let duration: Int?

    nonisolated
    struct Segment: Identifiable, Codable {
        let id: Int
        let text: String
        let start: TimeInterval
        let end: TimeInterval
        let translation: String?
        let status: Status?
    }

    struct Status: Codable {
        var isFavorited: Bool
        var bestScore: Int?
        var customPlaybackRate: Double?
    }
}

struct FavoritePodcastSegment: Identifiable {
    let id: String
    let podcastId: String
    let segmentId: Int
    let audioURL: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let translation: String?
}
