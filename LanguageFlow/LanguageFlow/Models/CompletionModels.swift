//
//  CompletionModels.swift
//  LanguageFlow
//

import Foundation
import SwiftData

@Model
final class CompletedPodcast {
    @Attribute(.unique) var podcastId: String
    var completedAt: Date
    
    init(podcastId: String) {
        self.podcastId = podcastId
        self.completedAt = Date()
    }
}
