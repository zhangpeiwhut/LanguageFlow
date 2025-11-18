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

struct DictionarySelection: Identifiable {
    let id = UUID()
    let term: String
}

struct WordToken: Identifiable {
    let id = UUID()
    let value: String
}

extension String {
    func wordTokens() -> [WordToken] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = self
        var tokens: [WordToken] = []
        tokenizer.enumerateTokens(in: startIndex..<endIndex) { range, _ in
            let fragment = String(self[range])
            tokens.append(WordToken(value: fragment))
            return true
        }
        return tokens
    }
}

struct SimilarityScorer {
    func score(reference: String, attempt: String) -> Int {
        let trimmedAttempt = attempt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAttempt.isEmpty else { return 0 }
        let lhs = reference.lowercased()
        let rhs = trimmedAttempt.lowercased()
        let distance = levenshtein(lhs, rhs)
        let maxCount = max(lhs.count, rhs.count)
        guard maxCount > 0 else { return 100 }
        let similarity = 1 - (Double(distance) / Double(maxCount))
        return Int((similarity * 100).rounded())
    }

    private func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let lhsCount = lhsChars.count
        let rhsCount = rhsChars.count

        var matrix = Array(repeating: Array(repeating: 0, count: rhsCount + 1), count: lhsCount + 1)
        for i in 0...lhsCount { matrix[i][0] = i }
        for j in 0...rhsCount { matrix[0][j] = j }

        for i in 1...lhsCount {
            for j in 1...rhsCount {
                if lhsChars[i - 1] == rhsChars[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(
                        matrix[i - 1][j] + 1,
                        matrix[i][j - 1] + 1,
                        matrix[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return matrix[lhsCount][rhsCount]
    }
}
