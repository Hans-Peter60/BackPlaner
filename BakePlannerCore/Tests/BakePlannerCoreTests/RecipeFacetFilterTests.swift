//
//  RecipeFacetFilterTests.swift
//  BakePlannerCoreTests
//
//  Whether a recipe passes the list's facets, and what the collections ask.
//

import BakePlannerCore
import Foundation
import Testing
@testable import BakePlannerCore

@Suite("The recipe list's facets")
struct RecipeFacetFilterTests {

    private let facets = RecipeFacets(totalMinutes: 900, activeMinutes: 30, longestRestMinutes: 720, duration: .overnight,
                                      dayFlows: [.eveningToMorning], leavening: .sourdough,
                                      grainShares: [.rye: 0.7, .wheat: 0.3], wholeGrainShare: 0.6, doughYield: 175,
                                      equipment: [.proofingBasket])
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("An empty filter passes everything and is not active")
    func empty() {
        let filter = RecipeFacetFilter()
        #expect(!filter.isActive)
        #expect(filter.matches(facets, history: .init(count: 0, lastDate: nil), now: now))
    }

    @Test("Every facet narrows on its own, and all of them combine")
    func facetsNarrow() {
        var filter = RecipeFacetFilter()
        filter.duration = .overnight
        filter.dayFlow = .eveningToMorning
        filter.leavening = .sourdough
        filter.grain = .rye
        filter.doughYield = .medium
        filter.equipment = .proofingBasket
        filter.lowWorkOnly = true
        #expect(filter.isActive)
        #expect(filter.matches(facets, history: .init(count: 0, lastDate: nil), now: now))

        filter.grain = .wholeGrain
        #expect(filter.matches(facets, history: .init(count: 0, lastDate: nil), now: now))
        filter.grain = .wheat
        #expect(!filter.matches(facets, history: .init(count: 0, lastDate: nil), now: now))
        filter.grain = nil
        filter.equipment = .loafTin
        #expect(!filter.matches(facets, history: .init(count: 0, lastDate: nil), now: now))
        filter.equipment = nil
        filter.dayFlow = .quick
        #expect(!filter.matches(facets, history: .init(count: 0, lastDate: nil), now: now))
    }

    @Test("The history facets: never, not for ninety days, favourites")
    func history() {
        var filter = RecipeFacetFilter()
        filter.history = .never
        #expect(filter.matches(facets, history: .init(count: 0, lastDate: nil), now: now))
        #expect(!filter.matches(facets, history: .init(count: 1, lastDate: now), now: now))

        filter.history = .longAgo
        #expect(filter.matches(facets, history: .init(count: 0, lastDate: nil), now: now))
        #expect(filter.matches(facets, history: .init(count: 3, lastDate: now.addingTimeInterval(-100 * 86_400)), now: now))
        #expect(!filter.matches(facets, history: .init(count: 3, lastDate: now.addingTimeInterval(-10 * 86_400)), now: now))

        filter.history = .favourites
        #expect(filter.matches(facets, history: .init(count: 2, lastDate: now, rating: 4), now: now))
        #expect(!filter.matches(facets, history: .init(count: 1, lastDate: now, rating: 5), now: now))
        #expect(!filter.matches(facets, history: .init(count: 4, lastDate: now, rating: 3), now: now))
    }

    @Test("Each collection is one facet, and all are active")
    func collections() {
        #expect(RecipeCollection.morning.filter.dayFlow == .eveningToMorning)
        #expect(RecipeCollection.quick.filter.dayFlow == .quick)
        #expect(RecipeCollection.sourdough.filter.leavening == .sourdough)
        #expect(RecipeCollection.longAgo.filter.history == .longAgo)
        #expect(RecipeCollection.favourites.filter.history == .favourites)
        #expect(RecipeCollection.allCases.allSatisfy { $0.filter.isActive })
    }
}
