import Foundation
import SwiftUI
import NaturalLanguage

struct SegmentPracticeState: Equatable {
    var isPlaying = false
    var isFavorited = false
    var isLooping = false
    var recognizedAttempt: String = ""
    var lastScore: Int?
    var isTranslationVisible: Bool = true
}
