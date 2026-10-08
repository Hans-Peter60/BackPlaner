//
//  BakeHistoryFactsTests.swift
//  BackPlanerTests
//

import Foundation
import Testing
@testable import BackPlaner

@Suite("Structured notes of a bake")
struct BakeHistoryFactsTests {

    private let german = Locale(identifier: "de_DE")
    private let english = Locale(identifier: "en_US")

    // MARK: Items

    @Test("Nothing recorded means no items and an empty entry")
    func emptyFacts() {
        let facts = BakeHistoryFacts()
        #expect(facts.isEmpty)
        #expect(facts.items(locale: german).isEmpty)
    }

    @Test("Blank texts and zero durations do not count as recorded")
    func blanksAreNotRecorded() {
        let facts = BakeHistoryFacts(bulkProofMinutes: 0, finalProofMinutes: nil, flour: "   ", outcome: "\n")
        #expect(facts.isEmpty)
    }

    @Test("Every fact appears once, in display order, formatted")
    func itemsInOrder() {
        let facts = BakeHistoryFacts(roomTemperature: 22,
                                     doughTemperature: 25.5,
                                     bulkProofMinutes: 210,
                                     finalProofMinutes: 45,
                                     flour: "Weizen 550",
                                     outcome: "offen, guter Ofentrieb")
        let items = facts.items(locale: german)

        #expect(items.map(\.kind) == [.roomTemperature, .doughTemperature, .bulkProof, .finalProof, .flour, .outcome])
        #expect(items[0].value == "22 °C")
        #expect(items[1].value == "25,5 °C")
        #expect(items[2].value == "3h 30m")
        #expect(items[3].value == "45m")
        #expect(items[4].value == "Weizen 550")
        #expect(items[5].value == "offen, guter Ofentrieb")
    }

    @Test("The one-line summary names the numbers and lists the texts as they are")
    func summaryLine() {
        let facts = BakeHistoryFacts(roomTemperature: 22, bulkProofMinutes: 90, flour: "Weizen 550", outcome: "offen")
        let line = facts.summaryLine(locale: german)
        #expect(line.hasSuffix(" · Weizen 550 · offen"))
        #expect(line.contains("22 °C"))
        #expect(line.contains("1h 30m"))
        #expect(BakeHistoryFacts().summaryLine(locale: german).isEmpty)
    }

    @Test("A temperature stays in Celsius in an English locale")
    func celsiusEverywhere() {
        let items = BakeHistoryFacts(roomTemperature: 22).items(locale: english)
        #expect(items.first?.value.contains("22") == true)
        #expect(items.first?.value.contains("C") == true)
        #expect(items.first?.value.contains("F") == false)
    }

    // MARK: Parsing

    @Test("Temperatures accept comma and point, and ignore a unit",
          arguments: [("22", 22.0), ("22,5", 22.5), ("22.5", 22.5), (" 24 °C ", 24.0), ("-2", -2.0)])
    func parseTemperature(input: String, expected: Double) {
        #expect(BakeHistoryFacts.parseTemperature(input) == expected)
    }

    @Test("An empty or unreadable temperature is not measured", arguments: ["", "   ", "warm", "22,5,1"])
    func unreadableTemperature(input: String) {
        #expect(BakeHistoryFacts.parseTemperature(input) == nil)
    }

    @Test("Minutes are whole numbers above zero", arguments: [("210", 210), ("45 Min", 45), ("0", nil), ("", nil), ("abc", nil)])
    func parseMinutes(input: String, expected: Int?) {
        #expect(BakeHistoryFacts.parseMinutes(input) == expected)
    }

    @Test("A stored value goes back into the field in the locale's spelling")
    func inputTexts() {
        #expect(BakeHistoryFacts.temperatureInput(22.5, locale: german) == "22,5")
        #expect(BakeHistoryFacts.temperatureInput(22.5, locale: english) == "22.5")
        #expect(BakeHistoryFacts.temperatureInput(22, locale: german) == "22")
        #expect(BakeHistoryFacts.temperatureInput(nil, locale: german) == "")
        #expect(BakeHistoryFacts.minutesInput(210) == "210")
        #expect(BakeHistoryFacts.minutesInput(0) == "")
    }

    // MARK: Keywords

    @Test("Tapping a chip adds the word, tapping it again removes it, typed text stays")
    func togglingKeywords() {
        var outcome = "etwas blass"
        outcome = BakeHistoryFacts.toggling("offen", in: outcome)
        #expect(outcome == "etwas blass, offen")
        #expect(BakeHistoryFacts.contains("offen", in: outcome))
        #expect(BakeHistoryFacts.contains("Offen", in: outcome))

        outcome = BakeHistoryFacts.toggling("guter Ofentrieb", in: outcome)
        #expect(outcome == "etwas blass, offen, guter Ofentrieb")

        outcome = BakeHistoryFacts.toggling("offen", in: outcome)
        #expect(outcome == "etwas blass, guter Ofentrieb")
        #expect(!BakeHistoryFacts.contains("offen", in: outcome))
    }

    @Test("Keywords are split at commas and trimmed")
    func keywordSplitting() {
        #expect(BakeHistoryFacts.keywords(in: " offen ,dicht,, saftig ") == ["offen", "dicht", "saftig"])
        #expect(BakeHistoryFacts.keywords(in: "").isEmpty)
    }

    // MARK: Comments

    @Test("The placeholder comment counts as no comment in every language",
          arguments: ["", "  ", "kein Kommentar erfasst", "no comment recorded", "aucun commentaire"])
    func placeholderComments(comment: String) {
        #expect(BakeHistoryFacts.isPlaceholderComment(comment))
    }

    @Test("A real comment is one")
    func realComment() {
        #expect(!BakeHistoryFacts.isPlaceholderComment("Kruste zu dunkel, nächstes Mal 230 °C."))
    }

    // MARK: Last time

    private struct Entry: Equatable {
        let name: String
        let date: Date
    }

    @Test("Last time is the newest entry that has already happened, not the one just planned")
    func lastCompletedEntry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let entries = [
            Entry(name: "planned", date: now.addingTimeInterval(3 * 3600)),
            Entry(name: "older",   date: now.addingTimeInterval(-14 * 86400)),
            Entry(name: "last",    date: now.addingTimeInterval(-7 * 86400)),
        ]

        let last = BakeHistoryFacts.lastCompleted(entries, date: \.date, now: now)
        #expect(last?.name == "last")
    }

    @Test("An entry dated exactly now has happened")
    func entryDatedNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let entries = [Entry(name: "now", date: now)]
        #expect(BakeHistoryFacts.lastCompleted(entries, date: \.date, now: now)?.name == "now")
    }

    @Test("Only future entries means there is no last time yet")
    func onlyFutureEntries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let entries = [Entry(name: "planned", date: now.addingTimeInterval(60))]
        #expect(BakeHistoryFacts.lastCompleted(entries, date: \.date, now: now) == nil)
        #expect(BakeHistoryFacts.lastCompleted([Entry](), date: \.date, now: now) == nil)
    }
}
