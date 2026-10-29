//
//  CoreDataLogicAdapters.swift
//  BackPlaner
//
//  The bridge from the Core Data objects to the plain structs the logic
//  works on. Keeping it here leaves DoughComposition, Rational,
//  BakeHistoryFacts and StarterFeedingFacts free of Core Data, so they can
//  later move into a platform-neutral package unchanged.
//

import Foundation
import CoreData

extension DoughComposition {
    static func components(of recipe: Recipe) -> [Component] {
        recipe.componentsArray.map { component in
            Component(name: component.name, ingredients: component.ingredientsArray.map { ingredient in
                Ingredient(name: ingredient.name,
                           grams: ingredient.normWeight > 0 ? ingredient.normWeight : ingredient.weight,
                           weight: ingredient.weight,
                           numerator: ingredient.num,
                           denominator: ingredient.denom)
            })
        }
    }
}

extension Rational.ComponentDependency {
    static func from(_ components: [Component]) -> [Rational.ComponentDependency] {
        let names = components.map { $0.name }
        return components.map { component in
            Rational.ComponentDependency(
                name: component.name,
                requires: requirements(
                    of: component.ingredientsArray.filter { $0.weight == 0 }.map { $0.name },
                    componentNames: names,
                    excluding: component.name
                )
            )
        }
    }
}

// MARK: - Bake history

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

// MARK: - Starter feeding log

extension StarterFeedingLog {

    /// Empty texts are stored as `nil`, so an untouched note never counts as
    /// written.
    var facts: StarterFeedingFacts {
        get {
            StarterFeedingFacts(peakMinutes: peakMinutes?.intValue,
                                 floatTestPassed: floatTestPassed?.boolValue,
                                 note: note ?? "")
        }
        set {
            peakMinutes = newValue.peakMinutes.flatMap { $0 > 0 ? NSNumber(value: $0) : nil }
            floatTestPassed = newValue.floatTestPassed.map { NSNumber(value: $0) }
            let note = newValue.note.trimmingCharacters(in: .whitespacesAndNewlines)
            self.note = note.isEmpty ? nil : note
        }
    }
}
