//
//  PlannedBakeEntriesTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The history entry a plan writes goes with the plan, unless someone wrote into it")
struct PlannedBakeEntriesTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var tomorrow: Date { now.addingTimeInterval(86_400) }
    private var yesterday: Date { now.addingTimeInterval(-86_400) }
    private var placeholder: String { AppSettings.generatedRecipeTexts(languageCode: "de").missingComment }

    private func entry(date: Date, comment: String = "", images: [Data] = [],
                       facts: BakeHistoryFacts = BakeHistoryFacts()) -> StoredBakeHistory {
        StoredBakeHistory(id: UUID().uuidString, recipeID: "r", date: date, comment: comment, images: images, facts: facts)
    }

    @Test("A future entry with the placeholder, in any language, and nothing else is untouched")
    func untouched() {
        #expect(PlannedBakeEntries.isUntouched(entry(date: tomorrow, comment: placeholder), now: now))
        #expect(PlannedBakeEntries.isUntouched(entry(date: tomorrow, comment: "no comment recorded"), now: now))
        #expect(PlannedBakeEntries.isUntouched(entry(date: tomorrow, comment: ""), now: now))
    }

    @Test("A past entry, a comment, a photo or a measurement keep the entry")
    func touched() {
        #expect(!PlannedBakeEntries.isUntouched(entry(date: yesterday, comment: placeholder), now: now))
        #expect(!PlannedBakeEntries.isUntouched(entry(date: tomorrow, comment: "Krume offen, gut"), now: now))
        #expect(!PlannedBakeEntries.isUntouched(entry(date: tomorrow, comment: placeholder, images: [Data([1])]), now: now))
        #expect(!PlannedBakeEntries.isUntouched(entry(date: tomorrow, comment: placeholder,
                                                      facts: BakeHistoryFacts(roomTemperature: 22)), now: now))
    }

    @Test("Removing from a store takes only the untouched entries of that recipe")
    func removeFromStore() throws {
        let recipes = InMemoryRecipeStore()
        let store = InMemoryBakeHistoryStore(recipes: recipes)
        let bread = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        var other = RecipeStoreContract.bread()
        other.name = "Anderes Brot"
        let otherBread = try recipes.add(other, firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)

        _ = try store.add(toRecipe: bread.id, date: tomorrow, comment: placeholder, images: [], facts: BakeHistoryFacts())
        let kept = try store.add(toRecipe: bread.id, date: tomorrow, comment: "Schon notiert", images: [], facts: BakeHistoryFacts())
        let past = try store.add(toRecipe: bread.id, date: yesterday, comment: placeholder, images: [], facts: BakeHistoryFacts())
        let foreign = try store.add(toRecipe: otherBread.id, date: tomorrow, comment: placeholder, images: [], facts: BakeHistoryFacts())

        let removed = try PlannedBakeEntries.remove(ofRecipe: bread.id, from: store, now: now)

        #expect(removed == 1)
        #expect(Set(try store.entries(ofRecipe: bread.id, includingImages: false).map(\.id)) == [kept.id, past.id])
        #expect(try store.entries(ofRecipe: otherBread.id, includingImages: false).map(\.id) == [foreign.id])
    }
}

@Suite("The feeding a starter's plan writes goes with the plan, unless a result was entered")
struct PlannedFeedingEntriesTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var tomorrow: Date { now.addingTimeInterval(86_400) }
    private var yesterday: Date { now.addingTimeInterval(-86_400) }

    private func feeding(date: Date, facts: StarterFeedingFacts = StarterFeedingFacts()) -> StoredStarterFeeding {
        StoredStarterFeeding(id: UUID().uuidString, recipeID: "r", date: date, facts: facts)
    }

    @Test("A future feeding without a result is untouched; a past one or one with a result is not")
    func untouched() {
        #expect(PlannedFeedingEntries.isUntouched(feeding(date: tomorrow), now: now))
        #expect(!PlannedFeedingEntries.isUntouched(feeding(date: yesterday), now: now))
        #expect(!PlannedFeedingEntries.isUntouched(feeding(date: tomorrow, facts: StarterFeedingFacts(peakMinutes: 300)), now: now))
        #expect(!PlannedFeedingEntries.isUntouched(feeding(date: tomorrow, facts: StarterFeedingFacts(floatTestPassed: true)), now: now))
        #expect(!PlannedFeedingEntries.isUntouched(feeding(date: tomorrow, facts: StarterFeedingFacts(note: "riecht gut")), now: now))
    }

    @Test("Removing from a store takes only the untouched feedings of that recipe")
    func removeFromStore() throws {
        let recipes = InMemoryRecipeStore()
        let store = InMemoryStarterFeedingLogStore(recipes: recipes)
        let starter = try recipes.add(RecipeStoreContract.bread(), firestoreId: nil, adjustedOn: nil, bakeHistoryFlag: false)
        _ = try store.add(toRecipe: starter.id, date: tomorrow, facts: StarterFeedingFacts())
        let kept = try store.add(toRecipe: starter.id, date: tomorrow, facts: StarterFeedingFacts(note: "schon notiert"))
        let past = try store.add(toRecipe: starter.id, date: yesterday, facts: StarterFeedingFacts())

        let removed = try PlannedFeedingEntries.remove(ofRecipe: starter.id, from: store, now: now)

        #expect(removed == 1)
        #expect(Set(try store.feedings(ofRecipe: starter.id).map(\.id)) == [kept.id, past.id])
    }
}
