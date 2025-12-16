//
//  PodcastCompletionManager.swift
//  LanguageFlow
//

import Foundation
import SwiftData

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
    
    func toggleCompletion(_ podcastId: String) {
        if isCompleted(podcastId) {
            // 标记为未完成
            let predicate = #Predicate<CompletedPodcast> { $0.podcastId == podcastId }
            let descriptor = FetchDescriptor(predicate: predicate)
            
            if let completed = try? modelContext.fetch(descriptor).first {
                modelContext.delete(completed)
                completedPodcastIds.remove(podcastId)
                try? modelContext.save()
            }
        } else {
            // 标记为完成
            let completed = CompletedPodcast(podcastId: podcastId)
            modelContext.insert(completed)
            completedPodcastIds.insert(podcastId)
            try? modelContext.save()
        }
    }
}
