//
//  SavedRecipeCollectionsTests.swift
//  BackPlanerTests
//
//  Saved collections: kept in the defaults, named, renamed, removed, and
//  the filter behind them survives the JSON round trip.
//

import BakePlannerCore
import Foundation
import Testing
@testable import BackPlaner

@Suite("Saved collections")
struct SavedRecipeCollectionsTests {

    private func freshDefaults() -> UserDefaults {
        let name = "SavedRecipeCollectionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private var sampleFilter: RecipeFacetFilter {
        var filter = RecipeFacetFilter()
        filter.leavening = .sourdough
        filter.equipment = .dutchOven
        filter.lowWorkOnly = true
        return filter
    }

    @Test("The filter survives JSON, with every facet and the toggle")
    func filterRoundTrip() throws {
        var filter = sampleFilter
        filter.duration = .overnight
        filter.dayFlow = .eveningToMorning
        filter.grain = .wholeGrain
        filter.doughYield = .soft
        filter.history = .favourites
        let data = try JSONEncoder().encode(filter)
        #expect(try JSONDecoder().decode(RecipeFacetFilter.self, from: data) == filter)
    }

    @Test("An unknown facet value or a missing key leaves the rest of the filter intact")
    func lenientDecoding() throws {
        let json = #"{"leavening":"sourdough","equipment":"woodFiredOven"}"#
        let filter = try JSONDecoder().decode(RecipeFacetFilter.self, from: Data(json.utf8))
        #expect(filter.leavening == .sourdough)
        #expect(filter.equipment == nil)
        #expect(!filter.lowWorkOnly)
    }

    @Test("Saved, found again by its facets, and still there in a new store on the same defaults")
    func addAndPersist() {
        let defaults = freshDefaults()
        let store = SavedRecipeCollectionStore(defaults: defaults, key: "test")
        let saved = store.add(name: "  Topfbrot ohne Arbeit ", filter: sampleFilter)
        #expect(saved?.name == "Topfbrot ohne Arbeit")
        #expect(store.collection(matching: sampleFilter)?.id == saved?.id)
        #expect(store.collection(matching: RecipeCollection.quick.filter) == nil)

        let again = SavedRecipeCollectionStore(defaults: defaults, key: "test")
        #expect(again.collections == store.collections)
        #expect(again.collections.first?.filter == sampleFilter)
    }

    @Test("No name or no facets: nothing is saved")
    func rejects() {
        let store = SavedRecipeCollectionStore(defaults: freshDefaults(), key: "test")
        #expect(store.add(name: "   ", filter: sampleFilter) == nil)
        #expect(store.add(name: "Leer", filter: RecipeFacetFilter()) == nil)
        #expect(store.collections.isEmpty)
    }

    @Test("Renamed and removed; an empty new name is ignored")
    func renameAndRemove() throws {
        let store = SavedRecipeCollectionStore(defaults: freshDefaults(), key: "test")
        let first = try #require(store.add(name: "Eins", filter: sampleFilter))
        let second = try #require(store.add(name: "Zwei", filter: RecipeCollection.morning.filter))
        store.rename(first.id, to: "Eins neu")
        store.rename(second.id, to: "")
        #expect(store.collections.map(\.name) == ["Eins neu", "Zwei"])
        store.remove(first.id)
        #expect(store.collections.map(\.name) == ["Zwei"])
    }
}
