//
//  AudioCacheManager.swift
//  LanguageFlow
//

import Foundation
import Alamofire

actor AudioCacheManager {
    static let shared = AudioCacheManager()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = documentsDirectory
            .appendingPathComponent("Favorites", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cachedAudioURL(forPodcastId podcastId: String) -> URL? {
        let destination = makeDestinationURL(forPodcastId: podcastId)
        return fileManager.fileExists(atPath: destination.path) ? destination : nil
    }

    @discardableResult
    func ensureAudioCached(forPodcastId podcastId: String, remoteURL: String) async throws -> URL {
        guard let url = URL(string: remoteURL) else {
            throw FavoriteError.invalidAudioURL
        }
        let destination = makeDestinationURL(forPodcastId: podcastId)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }
        do {
            let downloadDestination: DownloadRequest.Destination = { _, _ in
                return (destination, [.removePreviousFile, .createIntermediateDirectories])
            }
            _ = try await AF.download(url, to: downloadDestination)
                .validate()
                .serializingDownloadedFileURL()
                .value
            return destination
        } catch {
            throw FavoriteError.downloadFailed
        }
    }

    private func makeDestinationURL(forPodcastId podcastId: String) -> URL {
        return cacheDirectory.appendingPathComponent("\(podcastId).mp3")
    }

    func deleteCachedAudio(forPodcastId podcastId: String) {
        let url = cacheDirectory.appendingPathComponent("\(podcastId).mp3")
        try? fileManager.removeItem(at: url)
    }
}
