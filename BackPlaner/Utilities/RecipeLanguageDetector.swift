//
//  RecipeLanguageDetector.swift
//  BackPlaner
//

import Foundation
import NaturalLanguage

/// Works out which language a recipe is written in.
///
/// Recipes uploaded before the language was recorded carry no `sourceLanguage`,
/// and assuming German for those made a French recipe unreachable: the app took
/// its French text for the German original, so "translate into German" had
/// nothing left to do. Reading the language off the recipe's own text costs
/// nothing and needs no stored data.
enum RecipeLanguageDetector {

    /// The languages the app displays and translates between. Constraining the
    /// recognizer to them keeps a German recipe from being reported as Dutch,
    /// which the app could not do anything with anyway.
    static let supportedCodes = ["de", "en", "fr"]

    /// How sure the recognizer has to be. Below this the text is treated as
    /// undecidable and the caller keeps its own default.
    private static let minimumConfidence = 0.60

    /// Enough text to judge by. A recipe name alone ("Landbrot") says too
    /// little, so the instructions — which carry whole sentences — are included.
    private static let maximumSampleLength = 1_200
    private static let minimumSampleLength = 25

    /// Language of the recipe's own text, or nil when there is too little text
    /// or the result is too uncertain to act on.
    static func detectedLanguage(of recipe: RecipeFB) -> String? {
        detectedLanguage(in: sampleText(of: recipe))
    }

    /// Language of the text the recipe keeps under `languageCode`.
    ///
    /// Used to check a recorded language against what is actually written
    /// there: a recipe stamped "de" whose German slot holds French text was
    /// filed under the interface language instead of its own. The live values
    /// cannot answer this — they may be showing a translation right now.
    ///
    /// `minimumConfidence` is deliberately raised by callers that would
    /// overrule stored data with the result.
    static func detectedLanguage(
        of recipe: RecipeFB,
        storedUnder languageCode: String,
        minimumConfidence requiredConfidence: Double
    ) -> String? {
        detectedLanguage(
            in: cachedSampleText(of: recipe, languageCode: languageCode),
            minimumConfidence: requiredConfidence
        )
    }

    static func detectedLanguage(
        in text: String,
        minimumConfidence requiredConfidence: Double = minimumConfidence
    ) -> String? {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedText.count >= minimumSampleLength else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = supportedCodes.map { NLLanguage($0) }
        recognizer.processString(String(cleanedText.prefix(maximumSampleLength)))

        guard let best = recognizer.languageHypotheses(withMaximum: supportedCodes.count)
            .max(by: { $0.value < $1.value }),
              best.value >= requiredConfidence,
              supportedCodes.contains(best.key.rawValue) else {
            return nil
        }

        return best.key.rawValue
    }

    /// The recipe's prose, with the instructions first: they are full sentences
    /// and carry by far the most signal. Names of ingredients and components
    /// follow, the recipe name last — it is often a proper noun in any language.
    private static func sampleText(of recipe: RecipeFB) -> String {
        var parts = recipe.instructions.map(\.instruction)

        parts.append(recipe.summary)
        parts.append(contentsOf: recipe.components.map(\.name))
        parts.append(contentsOf: recipe.components.flatMap(\.ingredients).map(\.name))
        parts.append(recipe.name)

        return joined(parts)
    }

    /// The same prose, but taken from what the recipe stored for `languageCode`.
    /// Where a slot has nothing cached the live value stands in, so a partly
    /// filled cache still yields enough text to judge.
    private static func cachedSampleText(of recipe: RecipeFB, languageCode: String) -> String {
        var parts = recipe.instructions.map {
            $0.translations[languageCode]?.instruction ?? $0.instruction
        }

        let recipeText = recipe.translations[languageCode]
        parts.append(recipeText?.summary ?? recipe.summary)
        parts.append(contentsOf: recipe.components.map {
            $0.translations[languageCode]?.name ?? $0.name
        })
        parts.append(contentsOf: recipe.components.flatMap(\.ingredients).map {
            $0.translations[languageCode]?.name ?? $0.name
        })
        parts.append(recipeText?.name ?? recipe.name)

        return joined(parts)
    }

    private static func joined(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}
