//
//  PodcastAPI.swift
//  LanguageFlow
//

import Foundation
import Alamofire

class PodcastAPI {
    static let shared = PodcastAPI()

    private var baseURL: String {
        #if DEBUG
        return DebugConfig.baseURL
        #else
        return CommonConstants.baseURL
        #endif
    }

    func getAllChannels() async throws -> [Channel] {
        return try await NetworkManager.shared.request(
            "\(baseURL)/info/channels",
            method: .get
        )
        .validate()
        .serializingDecodable(ChannelsResponse.self)
        .value
        .channels
    }

    func getChannelDates(company: String, channel: String) async throws -> [Int] {
        return try await NetworkManager.shared.request(
            "\(baseURL)/info/channels/\(company)/\(channel)/dates",
            method: .get
        )
        .validate()
        .serializingDecodable(ChannelDatesResponse.self)
        .value
        .timestamps
    }

    func getChannelPodcasts(company: String, channel: String, timestamp: Int) async throws -> [PodcastSummary] {
        return try await NetworkManager.shared.request(
            "\(baseURL)/info/channels/\(company)/\(channel)/podcasts",
            method: .get,
            parameters: ["timestamp": timestamp]
        )
        .validate()
        .serializingDecodable(ChannelPodcastsResponse.self)
        .value
        .podcasts
    }

    func getChannelPodcastsPaged(company: String, channel: String, page: Int, limit: Int = 10) async throws -> ChannelPodcastsPagedResponse {
        return try await NetworkManager.shared.request(
            "\(baseURL)/info/channels/\(company)/\(channel)/podcasts/paged",
            method: .get,
            parameters: ["page": page, "limit": limit]
        )
        .validate()
        .serializingDecodable(ChannelPodcastsPagedResponse.self)
        .value
    }

    func getPodcastDetailById(_ id: String) async throws -> Podcast {
        return try await NetworkManager.shared.request(
            "\(baseURL)/info/detail/\(id)",
            method: .get
        )
        .validate()
        .serializingDecodable(PodcastDetailResponse.self)
        .value
        .podcast
    }
    
    func loadSegments(from tempURL: String) async throws -> [Podcast.Segment] {
        return try await AF.request(tempURL, method: .get)
            .validate()
            .serializingDecodable([Podcast.Segment].self)
            .value
    }
}

nonisolated
struct ChannelsResponse: Codable {
    let count: Int
    let channels: [Channel]
}

nonisolated
struct ChannelDatesResponse: Codable {
    let company: String
    let channel: String
    let count: Int
    let timestamps: [Int]
}

nonisolated
struct ChannelPodcastsResponse: Codable {
    let company: String
    let channel: String
    let timestamp: Int
    let count: Int
    let podcasts: [PodcastSummary]
}

nonisolated
struct ChannelPodcastsPagedResponse: Codable {
    let company: String
    let channel: String
    let page: Int
    let limit: Int
    let count: Int
    let total: Int
    let totalPages: Int?
    let podcasts: [PodcastSummary]

    enum CodingKeys: String, CodingKey {
        case company, channel, page, limit, count, total, podcasts
        case totalPages = "total_pages"
    }
}

nonisolated
struct PodcastDetailResponse: Codable {
    let podcast: Podcast
}
