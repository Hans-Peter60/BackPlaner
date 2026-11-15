//
//  BakeHistoryPhotoImportTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("A baking history from photos")
struct BakeHistoryPhotoImportTests {

    private let names = ["Bergkruste (Sauerteigbrot mit Roggen und Dinkel)", "Baguette mit Kochstück",
                         "Alm-Rezepte: Brioche mit Sauerteig", "Anstellgut Weizenvollkorn TA 190",
                         "Dinkelbrot", "Roggenmischbrot 70/30"]

    @Test("A title names the recipe by its own word, whole name or a prefix")
    func matching() {
        #expect(BakeHistoryPhotoImport.bestMatch(title: "Bergkruste", recipeNames: names)?.recipeName == names[0])
        #expect(BakeHistoryPhotoImport.bestMatch(title: "Bergkruste 2021", recipeNames: names)?.recipeName == names[0])
        #expect(BakeHistoryPhotoImport.bestMatch(title: "Baguettes", recipeNames: names)?.recipeName == names[1])
        #expect(BakeHistoryPhotoImport.bestMatch(title: "Brioche", recipeNames: names)?.recipeName == names[2])
        #expect(BakeHistoryPhotoImport.bestMatch(title: "Mein Dinkelbrot aus dem Topf", recipeNames: names)?.recipeName == names[4])
        #expect(BakeHistoryPhotoImport.score(title: "Baguette mit Kochstück", recipeName: names[1]) == 1)
    }

    @Test("A word that only trails another name scores lower than the bread's own name")
    func ranking() {
        let found = BakeHistoryPhotoImport.matches(title: "Sauerteigbrot", recipeNames: names)
        #expect(found.first?.recipeName == names[0])
        // "Dinkel" is in two names; the one that starts with it wins.
        #expect(BakeHistoryPhotoImport.bestMatch(title: "Dinkel", recipeNames: names)?.recipeName == names[4])
    }

    @Test("Nothing matches a title that names no recipe, an empty one or just a filler")
    func noMatch() {
        #expect(BakeHistoryPhotoImport.bestMatch(title: "Sonntagsfrühstück", recipeNames: names) == nil)
        #expect(BakeHistoryPhotoImport.bestMatch(title: "", recipeNames: names) == nil)
        #expect(BakeHistoryPhotoImport.bestMatch(title: "Brot", recipeNames: names) == nil)
        #expect(BakeHistoryPhotoImport.bestMatch(title: "IMG_2041", recipeNames: names) == nil)
    }

    @Test("A bake of the same recipe on the same day is a duplicate")
    func duplicates() {
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2021, month: 3, day: 14, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2021, month: 3, day: 14, hour: 19))!
        let nextDay = calendar.date(from: DateComponents(year: 2021, month: 3, day: 15, hour: 9))!
        let existing = [(recipeName: "Dinkelbrot", date: morning)]
        #expect(BakeHistoryPhotoImport.isDuplicate(recipeName: "Dinkelbrot", date: evening, existing: existing, calendar: calendar))
        #expect(!BakeHistoryPhotoImport.isDuplicate(recipeName: "Dinkelbrot", date: nextDay, existing: existing, calendar: calendar))
        #expect(!BakeHistoryPhotoImport.isDuplicate(recipeName: "Bergkruste", date: morning, existing: existing, calendar: calendar))
    }

    @Test("The EXIF date is read in the camera's clock; nonsense is nil")
    func exifDate() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let date = try #require(BakeHistoryPhotoImport.exifDate("2021:03:14 09:26:53", timeZone: zone))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts.year == 2021 && parts.month == 3 && parts.day == 14 && parts.hour == 9 && parts.minute == 26)
        #expect(BakeHistoryPhotoImport.exifDate("0000:00:00 00:00:00") == nil)
        #expect(BakeHistoryPhotoImport.exifDate("gestern") == nil)
    }
}
