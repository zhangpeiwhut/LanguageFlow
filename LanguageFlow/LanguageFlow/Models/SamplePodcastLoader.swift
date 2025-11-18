//
//  SamplePodcastLoader.swift
//  LanguageFlow
//

import Foundation

enum SamplePodcastLoader {
    private struct TranscriptPayload: Decodable {
        struct Segment: Decodable {
            let id: String
            let text: String
            let start: TimeInterval
            let end: TimeInterval
            let translation: String?
        }

        let segments: [Segment]
    }

    static func load() -> Podcast {
        let transcript = try! loadTranscript()
        let segments = transcript.segments.map { item in
            Podcast.Segment(
                id: item.id,
                text: item.text.trimmingCharacters(in: .whitespacesAndNewlines),
                start: item.start,
                end: item.end,
                translation: item.translation,
                status: nil
            )
        }

        return Podcast(
            id: "sample-house-votes-on-epstein-files",
            audioURL: "https://leo-test.fbcontent.cn/leo-cms/static-resources/1440746607471419392.mp3",
            title: "House Votes On Epstein Files, MAGA Coalition Cracks, Saudi Leader Visits White House",
            subtitle: "NPR News",
            timestamp: Int(Date().timeIntervalSince1970),
            language: "English",
            segments: segments,
            status: .init(isFavorited: false, bestScore: nil, customPlaybackRate: nil)
        )
    }

    private static func loadTranscript() throws -> TranscriptPayload {
        let data = try Data(contentsOf: resourceURL(named: "transcript", extension: "json"))
        return try JSONDecoder().decode(TranscriptPayload.self, from: data)
    }

    private static func resourceURL(named name: String, extension ext: String) throws -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

        // SwiftUI previews run inside a different bundle; fall back to the process directory.
        let fileManager = FileManager.default
        let bundlePath = fileManager.currentDirectoryPath
        let guesses = [
            URL(fileURLWithPath: bundlePath).appendingPathComponent("LanguageFlow/\(name).\(ext)"),
            URL(fileURLWithPath: bundlePath).appendingPathComponent("\(name).\(ext)")
        ]
        if let found = guesses.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return found
        }

        throw SampleLoadError.missingResource(name: name, ext: ext)
    }

    private enum SampleLoadError: Error {
        case missingResource(name: String, ext: String)
    }
}
