//
//  AudioCacheManager.swift
//  LanguageFlow
//

import Foundation

final class AudioCacheManager {
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
        guard let remoteURL = URL(string: remoteURL) else {
            throw FavoriteError.invalidAudioURL
        }
        let destination = makeDestinationURL(forPodcastId: podcastId)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: tempURL, to: destination)
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
