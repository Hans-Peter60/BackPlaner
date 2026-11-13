//
//  RecipeFacetFilterTests.swift
//  BackPlanerTests
//
//  The iPhone's side of the collections: every preset has a title and a
//  symbol. The filter itself is tested in the package (RecipeFacetFilterTests
//  in BakePlannerCoreTests).
//

import BakePlannerCore
import Foundation
import SwiftUI
import Testing
@testable import BackPlaner

@Suite("The recipe list's collections on the iPhone")
struct RecipeFacetFilterTests {

    @Test("Every preset collection has a symbol and a filter of its own")
    func presets() {
        let symbols = Set(RecipeCollection.allCases.map(\.systemImage))
        #expect(symbols.count == RecipeCollection.allCases.count)
        #expect(RecipeCollection.allCases.allSatisfy { !$0.systemImage.isEmpty && $0.filter.isActive })
    }

    @Test("The pantry collections are the two that need the pantry")
    func pantryCollections() {
        #expect(RecipeCollection.pantryCollections == [.pantry, .useUp])
    }
}
