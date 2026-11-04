//
//  RecipeVariantsTests.swift
//  BakePlannerCoreTests
//
//  The texts both apps show for recipe variants.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Recipe variant texts")
struct RecipeVariantsTests {

    @Test("A variant made by hand is named like an adjusted copy, with the date")
    func variantName() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let name = AdjustedRecipe.variantName(original: "Landbrot", on: date)
        #expect(name.hasPrefix("Landbrot – Variante ("))
        #expect(AdjustedRecipe.hasDatedSuffix(name))
        #expect(AdjustedRecipe.baseName(of: name) == "Landbrot")
    }

    @Test("How a variant baked: not yet, or how often and the last time")
    func bakesText() {
        #expect(RecipeVariantText.bakes(completedCount: 0, lastDateText: "", lastFactsLine: "") == "Noch nicht gebacken")
        #expect(RecipeVariantText.bakes(completedCount: 3, lastDateText: "12.10.2026", lastFactsLine: "★★★★ · offen")
                == "3-mal gebacken · zuletzt 12.10.2026: ★★★★ · offen")
        #expect(RecipeVariantText.bakes(completedCount: 1, lastDateText: "12.10.2026", lastFactsLine: "")
                == "1-mal gebacken · zuletzt 12.10.2026")
    }
}
