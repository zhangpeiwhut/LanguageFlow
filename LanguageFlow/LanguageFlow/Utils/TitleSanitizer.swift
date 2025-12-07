//
//  TitleSanitizer.swift
//  LanguageFlow
//
//  Helpers to normalize podcast titles/translations by dropping trailing dates.
//

import Foundation

extension String {
    /// Removes trailing date-like suffixes appended with " - ".
    /// Examples handled:
    /// "Title - March 07, 2025" -> "Title"
    /// "标题 - 2025年3月7日" -> "标题"
    func removingTrailingDateSuffix() -> String {
        guard let separatorRange = range(of: " - ", options: .backwards) else {
            return self
        }

        let suffix = self[separatorRange.upperBound...]
        // Only strip if suffix looks like a date (contains digits).
        guard suffix.rangeOfCharacter(from: .decimalDigits) != nil else {
            return self
        }

        let trimmed = self[..<separatorRange.lowerBound].trimmingCharacters(in: .whitespaces)
        return trimmed
    }
}
