import Foundation
import SwiftUI
import NaturalLanguage

struct SegmentPracticeState: Equatable {
    var playbackRate: Double = 1.0
    var isPlaying = false
    var isFavorited = false
    var recognizedAttempt: String = ""
    var lastScore: Int?
    var isTranslationVisible: Bool = true
}
