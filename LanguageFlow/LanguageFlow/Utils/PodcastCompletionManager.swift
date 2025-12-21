//
//  PodcastCompletionManager.swift
//  LanguageFlow
//

import Foundation
import SwiftData
import Observation

@Observable
final class PodcastCompletionManager {
    private let modelContext: ModelContext
    private var completedPodcastIds: Set<String> = []
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadCompletedPodcasts()
    }
    
    private func loadCompletedPodcasts() {
        let descriptor = FetchDescriptor<CompletedPodcast>()
        if let completed = try? modelContext.fetch(descriptor) {
            completedPodcastIds = Set(completed.map { $0.podcastId })
        }
    }
    
    func isCompleted(_ podcastId: String) -> Bool {
        completedPodcastIds.contains(podcastId)
    }

    func markCompleted(_ podcastId: String) {
        guard !isCompleted(podcastId) else { return }
        let completed = CompletedPodcast(podcastId: podcastId)
        modelContext.insert(completed)
        completedPodcastIds.insert(podcastId)
        try? modelContext.save()
    }

    func toggleCompletion(_ podcastId: String) {
        if isCompleted(podcastId) {
            removeCompletion(podcastId)
        } else {
            markCompleted(podcastId)
        }
    }

    private func removeCompletion(_ podcastId: String) {
        guard isCompleted(podcastId) else { return }
        let descriptor = FetchDescriptor<CompletedPodcast>(
            predicate: #Predicate { $0.podcastId == podcastId }
        )
        if let completed = try? modelContext.fetch(descriptor) {
            completed.forEach { modelContext.delete($0) }
        }
        completedPodcastIds.remove(podcastId)
        try? modelContext.save()
    }
}
