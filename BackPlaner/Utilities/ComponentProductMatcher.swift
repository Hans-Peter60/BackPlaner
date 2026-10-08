//
//  ComponentProductMatcher.swift
//  BackPlaner
//
//  Recognises an ingredient row that stands for another component of the
//  same recipe — "gesamter Sauerteig" in the main dough — so that the
//  component's content is not counted twice, by the total ingredients, the
//  shopping list or the dough yield.
//

import Foundation

enum ComponentProductMatcher {

    /// The index of the component the row refers to, or nil for a raw
    /// ingredient.
    ///
    /// An exact name match counts whatever the weight says: "200 g Sauerteig"
    /// uses part of the component "Sauerteig". A row without a weight whose
    /// numerator equals its denominator stands for the whole product and may
    /// name the component loosely ("gesamte Sauerteigstufe 1" for the
    /// component "Sauerteig Stufe 1").
    static func referencedComponent(name: String,
                                    weight: Double,
                                    numerator: Int,
                                    denominator: Int,
                                    componentNames: [String]) -> Int? {
        // The stage-keeping comparison first: with "Sauerteig Stufe 1" and
        // "Sauerteig Stufe 2" both reduced to "sauerteig", the product name
        // alone could not tell which stage "gesamte Sauerteigstufe 2" means.
        let compactName = compactName(name)
        if !compactName.isEmpty,
           let index = componentNames.map(Self.compactName).firstIndex(of: compactName) {
            return index
        }

        let productName = normalizedProductName(name)
        guard !productName.isEmpty else { return nil }
        let productNames = componentNames.map(normalizedProductName)

        if let index = productNames.firstIndex(of: productName) {
            return index
        }

        let representsWholeProduct = weight == 0 && denominator != 0 && numerator == denominator
        guard representsWholeProduct else { return nil }

        return productNames.firstIndex { componentName in
            let shortestNameLength = min(productName.count, componentName.count)
            return shortestNameLength >= 5
                && (productName.contains(componentName) || componentName.contains(productName))
        }
    }

    /// The product name with the stage kept and every space and punctuation
    /// mark dropped, so "Sauerteig Stufe 1" and "Sauerteigstufe 1" are equal.
    static func compactName(_ name: String) -> String {
        var normalizedName = IngredientNameNormalizer.comparisonKey(name)

        for prefix in ["gesamter ", "gesamte ", "gesamtes ", "ganzer ", "ganze ", "ganzes "] where normalizedName.hasPrefix(prefix) {
            normalizedName.removeFirst(prefix.count)
            break
        }

        if let separatorIndex = normalizedName.firstIndex(where: { "/(".contains($0) }) {
            normalizedName = String(normalizedName[..<separatorIndex])
        }

        return String(normalizedName.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// A name reduced to what identifies the product: no "gesamter", no
    /// parenthesis or slash remark, no "Stufe …" suffix, no temperature,
    /// case- and accent-insensitive.
    static func normalizedProductName(_ name: String) -> String {
        var normalizedName = IngredientNameNormalizer.comparisonKey(name)

        for prefix in ["gesamter ", "gesamte ", "gesamtes ", "ganzer ", "ganze ", "ganzes "] where normalizedName.hasPrefix(prefix) {
            normalizedName.removeFirst(prefix.count)
            break
        }

        if let separatorIndex = normalizedName.firstIndex(where: { "/(".contains($0) }) {
            normalizedName = String(normalizedName[..<separatorIndex])
        }

        if let stageRange = normalizedName.range(of: " stufe ") {
            normalizedName = String(normalizedName[..<stageRange.lowerBound])
        }

        return normalizedName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
