//
//  PodcastAPI.swift
//  LanguageFlow
//
//  API服务类，用于调用后端podcast接口
//

import Foundation
import Alamofire

class PodcastAPI {
    static let shared = PodcastAPI()
    
    private let baseURL: String
    
    init(baseURL: String = "https://elegantfish.online/podcast") {
        self.baseURL = baseURL
    }

    func getAllChannels() async throws -> [Channel] {
        return try await AF.request(
            "\(baseURL)/channels",
            method: .get
        )
        .validate()
        .serializingDecodable(ChannelsResponse.self)
        .value
        .channels
    }

    func getChannelDates(company: String, channel: String) async throws -> [Int] {
        return try await AF.request(
            "\(baseURL)/channels/\(company)/\(channel)/dates",
            method: .get
        )
        .validate()
        .serializingDecodable(ChannelDatesResponse.self)
        .value
        .timestamps
    }

    func getChannelPodcasts(company: String, channel: String, timestamp: Int) async throws -> [PodcastSummary] {
        return try await AF.request(
            "\(baseURL)/channels/\(company)/\(channel)/podcasts",
            method: .get,
            parameters: ["timestamp": timestamp]
        )
        .validate()
        .serializingDecodable(ChannelPodcastsResponse.self)
        .value
        .podcasts
    }

    func getPodcastDetailById(_ id: String) async throws -> PodcastItem {
        return try await AF.request(
            "\(baseURL)/detail/\(id)",
            method: .get
        )
        .validate()
        .serializingDecodable(PodcastDetailResponse.self)
        .value
        .podcast
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
struct PodcastDetailResponse: Codable {
    let podcast: PodcastItem
}

