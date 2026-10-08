//
//  BakeHistoryFacts.swift
//  BackPlaner
//
//  The part of a bake-history entry that helps with the next bake of the
//  same recipe: the temperatures, how long the dough really proofed, which
//  flour went in, and a few words on crumb and oven spring. Free text and
//  stars alone did not let anyone get better from one bake to the next.
//

import Foundation
import CoreData
import SwiftUI

struct BakeHistoryFacts: Equatable {

    /// Room temperature in °C.
    var roomTemperature: Double?
    /// Dough temperature in °C.
    var doughTemperature: Double?
    /// The bulk proof (Stockgare) as it actually took, in minutes.
    var bulkProofMinutes: Int?
    /// The final proof (Stückgare) as it actually took, in minutes.
    var finalProofMinutes: Int?
    /// The flour used, free text ("Weizen 550, Drax-Mühle").
    var flour: String = ""
    /// Crumb and oven spring in a few keywords, comma-separated.
    var outcome: String = ""

    init(roomTemperature: Double? = nil,
         doughTemperature: Double? = nil,
         bulkProofMinutes: Int? = nil,
         finalProofMinutes: Int? = nil,
         flour: String = "",
         outcome: String = "") {
        self.roomTemperature = roomTemperature
        self.doughTemperature = doughTemperature
        self.bulkProofMinutes = bulkProofMinutes
        self.finalProofMinutes = finalProofMinutes
        self.flour = flour
        self.outcome = outcome
    }

    /// True when nothing at all was recorded.
    var isEmpty: Bool {
        items().isEmpty
    }

    // MARK: - Items

    /// The kinds of fact, in the order they are shown.
    enum Kind: CaseIterable, Hashable {
        case roomTemperature
        case doughTemperature
        case bulkProof
        case finalProof
        case flour
        case outcome

        /// The label of the row in a form or on the "last time" card.
        var title: LocalizedStringKey {
            switch self {
            case .roomTemperature:  return "Raumtemperatur"
            case .doughTemperature: return "Teigtemperatur"
            case .bulkProof:        return "Stockgare"
            case .finalProof:       return "Stückgare"
            case .flour:            return "Mehl"
            case .outcome:          return "Krume / Ofentrieb"
            }
        }

        /// The label in a one-line summary; flour and outcome speak for
        /// themselves there and carry none. A `String` in the in-app
        /// language (not a `LocalizedStringKey`) because the summary is
        /// assembled as one string, see `summaryLine()`.
        var shortTitle: String? {
            let bundle = AppSettings.localizationBundle
            let locale = AppSettings.locale
            switch self {
            case .roomTemperature:  return String(localized: "Raum", bundle: bundle, locale: locale, comment: "Kurz für Raumtemperatur")
            case .doughTemperature: return String(localized: "Teig", bundle: bundle, locale: locale, comment: "Kurz für Teigtemperatur")
            case .bulkProof:        return String(localized: "Stockgare", bundle: bundle, locale: locale)
            case .finalProof:       return String(localized: "Stückgare", bundle: bundle, locale: locale)
            case .flour, .outcome:  return nil
            }
        }

        var systemImage: String {
            switch self {
            case .roomTemperature:  return "thermometer.medium"
            case .doughTemperature: return "thermometer.variable"
            case .bulkProof:        return "hourglass"
            case .finalProof:       return "hourglass.bottomhalf.filled"
            case .flour:            return "leaf"
            case .outcome:          return "text.bubble"
            }
        }
    }

    /// One recorded fact, formatted for display.
    struct Item: Identifiable, Equatable {
        let kind: Kind
        let value: String
        var id: Kind { kind }
    }

    /// The facts that were recorded, formatted, in display order. Numbers
    /// follow `locale`; the free texts are shown as typed.
    func items(locale: Locale = AppSettings.locale) -> [Item] {
        var items = [Item]()
        if let roomTemperature {
            items.append(Item(kind: .roomTemperature, value: Self.temperatureText(roomTemperature, locale: locale)))
        }
        if let doughTemperature {
            items.append(Item(kind: .doughTemperature, value: Self.temperatureText(doughTemperature, locale: locale)))
        }
        if let bulkProofMinutes, bulkProofMinutes > 0 {
            items.append(Item(kind: .bulkProof, value: Self.durationText(bulkProofMinutes)))
        }
        if let finalProofMinutes, finalProofMinutes > 0 {
            items.append(Item(kind: .finalProof, value: Self.durationText(finalProofMinutes)))
        }
        let flour = flour.trimmingCharacters(in: .whitespacesAndNewlines)
        if !flour.isEmpty {
            items.append(Item(kind: .flour, value: flour))
        }
        let outcome = outcome.trimmingCharacters(in: .whitespacesAndNewlines)
        if !outcome.isEmpty {
            items.append(Item(kind: .outcome, value: outcome))
        }
        return items
    }

    /// The recorded facts in one line — "Raum 22 °C · Teig 25 °C · Stockgare
    /// 3h 30m · Weizen 550 · offen" — for a list row or a gallery tile.
    /// Empty when nothing was recorded.
    func summaryLine(locale: Locale = AppSettings.locale) -> String {
        items(locale: locale)
            .map { item in
                if let shortTitle = item.kind.shortTitle {
                    return "\(shortTitle) \(item.value)"
                }
                return item.value
            }
            .joined(separator: " · ")
    }

    // MARK: - Formatting and parsing

    /// "22 °C", "22,5 °C" — never converted to Fahrenheit, whatever the
    /// locale: the value was measured in Celsius and is shown as such.
    static func temperatureText(_ celsius: Double, locale: Locale) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated,
                                    usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...1)))
                .locale(locale))
    }

    /// The duration in the form the plan table uses ("3h 30m", "45m").
    static func durationText(_ minutes: Int) -> String {
        Rational.displayHoursMinutes(minutes)
    }

    /// A temperature as typed: "22", "22,5" or "22.5"; anything else, and an
    /// empty field, is "not measured".
    static func parseTemperature(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "°C", with: "")
            .replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// A number of minutes as typed. Zero and anything that is not a whole
    /// number count as "not recorded".
    static func parseMinutes(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    /// The text to put into a temperature field for an existing value, with
    /// the decimal separator of `locale`.
    static func temperatureInput(_ celsius: Double?, locale: Locale = AppSettings.locale) -> String {
        guard let celsius else { return "" }
        return celsius.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
    }

    static func minutesInput(_ minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "" }
        return String(minutes)
    }

    // MARK: - Outcome keywords

    /// The words offered as chips under the crumb / oven-spring field. Typed
    /// text in the app's language, since they become part of the stored
    /// entry — like the placeholder comment, see `AppSettings.generatedRecipeTexts`.
    enum OutcomeKeyword: CaseIterable, Identifiable {
        // Crumb
        case open, dense, moist, dry, even, largePores, gummy
        // Oven spring
        case goodSpring, littleSpring, torn, flat

        var id: Self { self }

        static let crumb: [OutcomeKeyword] = [.open, .dense, .moist, .dry, .even, .largePores, .gummy]
        static let ovenSpring: [OutcomeKeyword] = [.goodSpring, .littleSpring, .torn, .flat]

        var text: String {
            let bundle = AppSettings.localizationBundle
            let locale = AppSettings.locale
            switch self {
            case .open:         return String(localized: "offen", bundle: bundle, locale: locale, comment: "Krume")
            case .dense:        return String(localized: "dicht", bundle: bundle, locale: locale, comment: "Krume")
            case .moist:        return String(localized: "saftig", bundle: bundle, locale: locale, comment: "Krume")
            case .dry:          return String(localized: "trocken", bundle: bundle, locale: locale, comment: "Krume")
            case .even:         return String(localized: "gleichmäßig", bundle: bundle, locale: locale, comment: "Krume")
            case .largePores:   return String(localized: "großporig", bundle: bundle, locale: locale, comment: "Krume")
            case .gummy:        return String(localized: "klitschig", bundle: bundle, locale: locale, comment: "Krume")
            case .goodSpring:   return String(localized: "guter Ofentrieb", bundle: bundle, locale: locale, comment: "Ofentrieb")
            case .littleSpring: return String(localized: "wenig Ofentrieb", bundle: bundle, locale: locale, comment: "Ofentrieb")
            case .torn:         return String(localized: "eingerissen", bundle: bundle, locale: locale, comment: "Ofentrieb")
            case .flat:         return String(localized: "flach geblieben", bundle: bundle, locale: locale, comment: "Ofentrieb")
            }
        }
    }

    /// The keywords in `outcome`, split at the commas.
    static func keywords(in outcome: String) -> [String] {
        outcome
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// `outcome` with `keyword` added when it is missing and removed when it
    /// is there. Whatever else was typed stays.
    static func toggling(_ keyword: String, in outcome: String) -> String {
        var words = keywords(in: outcome)
        if let index = words.firstIndex(where: { $0.caseInsensitiveCompare(keyword) == .orderedSame }) {
            words.remove(at: index)
        } else {
            words.append(keyword)
        }
        return words.joined(separator: ", ")
    }

    static func contains(_ keyword: String, in outcome: String) -> Bool {
        keywords(in: outcome).contains { $0.caseInsensitiveCompare(keyword) == .orderedSame }
    }

    // MARK: - Comments

    /// Whether `comment` says nothing: empty, or the placeholder the app
    /// writes when reminders are set, in any of its languages — the entry
    /// may have been created with the app in another language.
    static func isPlaceholderComment(_ comment: String) -> Bool {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return ["de", "en", "fr"].contains {
            AppSettings.generatedRecipeTexts(languageCode: $0).missingComment == trimmed
        }
    }

    // MARK: - Which entry is "last time"

    /// The latest of `entries` that has already happened. Setting reminders
    /// creates an entry dated at the end of the planned bake, so the newest
    /// entry is often still in the future and says nothing yet; the one to
    /// learn from is the newest with a date at or before `now`.
    static func lastCompleted<Entry>(_ entries: [Entry], date: (Entry) -> Date, now: Date) -> Entry? {
        entries
            .filter { date($0) <= now }
            .max { date($0) < date($1) }
    }
}

// MARK: - Core Data

extension BakeHistory {

    /// The structured part of the entry. Empty texts are stored as `nil`, so
    /// an untouched field never counts as recorded.
    var facts: BakeHistoryFacts {
        get {
            BakeHistoryFacts(roomTemperature: roomTemperature?.doubleValue,
                             doughTemperature: doughTemperature?.doubleValue,
                             bulkProofMinutes: bulkProofMinutes?.intValue,
                             finalProofMinutes: finalProofMinutes?.intValue,
                             flour: flour ?? "",
                             outcome: outcome ?? "")
        }
        set {
            roomTemperature   = newValue.roomTemperature.map { NSNumber(value: $0) }
            doughTemperature  = newValue.doughTemperature.map { NSNumber(value: $0) }
            bulkProofMinutes  = newValue.bulkProofMinutes.flatMap { $0 > 0 ? NSNumber(value: $0) : nil }
            finalProofMinutes = newValue.finalProofMinutes.flatMap { $0 > 0 ? NSNumber(value: $0) : nil }
            let flour = newValue.flour.trimmingCharacters(in: .whitespacesAndNewlines)
            self.flour = flour.isEmpty ? nil : flour
            let outcome = newValue.outcome.trimmingCharacters(in: .whitespacesAndNewlines)
            self.outcome = outcome.isEmpty ? nil : outcome
        }
    }

    /// Whether the entry holds anything worth reading: a fact, a real
    /// comment or a photo.
    var hasNotes: Bool {
        !facts.isEmpty
            || !BakeHistoryFacts.isPlaceholderComment(comment)
            || !(images ?? []).isEmpty
    }
}

extension Recipe {

    /// The entry of the recipe's last bake that has already taken place, if
    /// there is one — what "last time" refers to when the recipe is planned
    /// again.
    func lastCompletedBakeHistory(now: Date = Date()) -> BakeHistory? {
        BakeHistoryFacts.lastCompleted(bakeHistoriesArray, date: \.date, now: now)
    }
}
