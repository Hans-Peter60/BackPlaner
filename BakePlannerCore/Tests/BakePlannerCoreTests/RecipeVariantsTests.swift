//
//  RecipeVariantsTests.swift
//  BakePlannerCoreTests
//
//  How variants are named, and the texts both apps show for them.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Recipe variant names and texts")
struct RecipeVariantsTests {

    @Test("A variant takes the next free number of its family")
    func variantName() {
        #expect(AdjustedRecipe.variantName(original: "Landbrot", among: ["Landbrot", "Roggenbrot"]) == "Landbrot V1")
        #expect(AdjustedRecipe.variantName(original: "Landbrot", among: ["Landbrot", "Landbrot V1", "Landbrot V2"])
                == "Landbrot V3")
        // A deleted number is not handed out again.
        #expect(AdjustedRecipe.variantName(original: "Landbrot", among: ["Landbrot", "Landbrot V3"]) == "Landbrot V4")
        // A variant of a variant joins the family instead of stacking suffixes.
        #expect(AdjustedRecipe.variantName(original: "Landbrot V1", among: ["Landbrot", "Landbrot V1", "Landbrot V2"])
                == "Landbrot V3")
        // Other families and the dated copies of earlier versions do not count.
        #expect(AdjustedRecipe.variantName(original: "Landbrot",
                                           among: ["Landbrot V9x", "Landbrot – Dinkelmehl 630 (14.10.2026)", "Landbrötchen V4"])
                == "Landbrot V1")
        // A dash in the name stays part of the family.
        #expect(AdjustedRecipe.variantName(original: "Brot – Sonntag", among: ["Brot – Sonntag V1"]) == "Brot – Sonntag V2")
    }

    @Test("Family name and number of a variant name")
    func familyAndNumber() {
        #expect(AdjustedRecipe.familyName(of: "Landbrot V2") == "Landbrot")
        #expect(AdjustedRecipe.familyName(of: " Landbrot V12 ") == "Landbrot")
        #expect(AdjustedRecipe.familyName(of: "Brot – Sonntag") == "Brot – Sonntag")
        #expect(AdjustedRecipe.variantNumber(of: "Landbrot V12") == 12)
        #expect(AdjustedRecipe.variantNumber(of: "Landbrot") == nil)
        #expect(AdjustedRecipe.variantNumber(of: "Landbrot V") == nil)
        #expect(AdjustedRecipe.variantNumber(of: "LandbrotV2") == nil)
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
