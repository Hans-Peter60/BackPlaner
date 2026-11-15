//
//  BakeHistoryPhotoImport.swift
//  BakePlannerCore
//
//  Years of bread photos become a baking history: each photo's date and,
//  where the photo carries one, its title; the title is matched against
//  the names of the baker's own recipes. Reading the photos and comparing
//  pictures is the app's job; the name matching and the duplicate rule
//  live here.
//

import Foundation

public enum BakeHistoryPhotoImport {

    /// A recipe a photo's title points to, with how sure the match is
    /// (1 is the same name, 0.5 the least the import still proposes).
    public struct NameMatch: Equatable {
        public let recipeName: String
        public let score: Double

        public init(recipeName: String, score: Double) {
            self.recipeName = recipeName
            self.score = score
        }
    }

    /// Below this score a title names no recipe.
    public static let minimumScore = 0.5

    /// The words of a text that tell recipes apart: lowercase, without
    /// accents and punctuation, at least three letters, numbers and the
    /// words every bread photo may carry ("brot", "mein") left out.
    public static func tokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
        return folded.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && Int($0) == nil && !fillers.contains($0) }
    }

    static let fillers: Set<String> = ["brot", "brote", "mein", "meine", "unser", "unsere", "und", "mit", "aus", "der", "die", "das",
                                       "bread", "loaf", "with", "and", "the", "pain", "avec"]

    /// How well a title names a recipe: the same words (or one the prefix
    /// of the other, "baguettes" for "baguette") shared, measured against
    /// the shorter of the two; a title that is the whole name, or contains
    /// it, counts fully.
    public static func score(title: String, recipeName: String) -> Double {
        let titleTokens = tokens(title)
        let nameTokens = tokens(recipeName)
        guard !titleTokens.isEmpty, !nameTokens.isEmpty else { return 0 }
        let foldedTitle = titleTokens.joined(separator: " ")
        let foldedName = nameTokens.joined(separator: " ")
        if foldedTitle == foldedName { return 1 }
        if foldedName.count >= 4, foldedTitle.contains(foldedName) { return 0.95 }
        if foldedTitle.count >= 4, foldedName.contains(foldedTitle) { return 0.9 }

        var shared = 0
        for word in titleTokens where nameTokens.contains(where: { same($0, word) }) {
            shared += 1
        }
        guard shared > 0 else { return 0 }
        let base = Double(shared) / Double(min(titleTokens.count, nameTokens.count))
        // A match on the name's first word — the bread's own name, before
        // "mit Roggen und Dinkel" — weighs more than one on a trailing word.
        let firstWordMatches = nameTokens.first.map { first in titleTokens.contains { same($0, first) } } ?? false
        return min(1, base * (firstWordMatches ? 1 : 0.75))
    }

    /// Equal words, or one the start of the other from five letters on.
    static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = a.count < b.count ? a : b
        let longer = a.count < b.count ? b : a
        return shorter.count >= 5 && longer.hasPrefix(shorter)
    }

    /// Every recipe a title may name, best first; only those at or above
    /// `minimumScore`.
    public static func matches(title: String, recipeNames: [String]) -> [NameMatch] {
        recipeNames
            .map { NameMatch(recipeName: $0, score: score(title: title, recipeName: $0)) }
            .filter { $0.score >= minimumScore }
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.recipeName.count < rhs.recipeName.count
            }
    }

    public static func bestMatch(title: String, recipeNames: [String]) -> NameMatch? {
        matches(title: title, recipeNames: recipeNames).first
    }

    /// Whether the history already has a bake of this recipe on that day,
    /// so a photo imported twice does not make two bakes.
    public static func isDuplicate(recipeName: String, date: Date,
                                   existing: [(recipeName: String, date: Date)],
                                   calendar: Calendar = .current) -> Bool {
        existing.contains { $0.recipeName == recipeName && calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// The EXIF date "2021:03:14 09:26:53" as a date in the current time
    /// zone (the camera's clock), nil for anything else.
    public static func exifDate(_ text: String, timeZone: TimeZone = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        for format in ["yyyy:MM:dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy:MM:dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed), date.timeIntervalSince1970 > 0 { return date }
        }
        return nil
    }
}
