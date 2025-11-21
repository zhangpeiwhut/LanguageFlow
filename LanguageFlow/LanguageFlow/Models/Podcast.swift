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

struct PodcastItem: Codable, Identifiable {
    let id: String
    let company: String
    let channel: String
    let audioURL: String
    let title: String?
    let subtitle: String?
    let timestamp: Int
    let language: String

    var dateString: String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    var formattedDate: String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
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
        let id: String
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

extension Podcast {
    static var sample: Podcast { SamplePodcastLoader.load() }
}
