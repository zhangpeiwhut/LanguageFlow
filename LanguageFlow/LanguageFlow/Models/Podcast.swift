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
    let duration: Int?
}

struct Podcast: Codable, Identifiable {
    let id: String
    let audioURL: String
    let title: String?
    let subtitle: String?
    let timestamp: Int
    let language: String
    let segments: [Segment]
    let status: Status?

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
