//
//  DoughTypeGuess.swift
//  BakePlannerCore
//
//  Which kind of dough a recipe makes, for the tin calculator's dough type:
//  light wheat, mixed, or rye and wholegrain. Read from the flours and the
//  seeds of the recipe, the way the German bread names are drawn: a
//  Weizenbrot has at least 90 % wheat, a Roggenbrot at least 90 % rye, and
//  everything between is a Mischbrot. Wholegrain and coarse meal count with
//  the rye because they rise as little, and a loaf with a lot of seeds is
//  as dense as one of rye.
//

import Foundation

extension DoughWeightFromTin {

    /// Rye, wholegrain and coarse meal as a share of all flour from here on
    /// make a dough that fills a tin like rye does.
    public static let heavyFlourShareForRye = 0.5
    /// Seeds, flakes and nuts as a share of the flour from here on do the same.
    public static let seedShareForRye = 0.15
    /// Up to this share of rye, wholegrain and dark flours a dough is still
    /// a light wheat dough …
    public static let heavyFlourShareForLightWheat = 0.1
    /// … as long as it carries less than this in seeds.
    public static let seedShareForLightWheat = 0.05

    /// Coarse meal of any grain is wholegrain: "Weizenschrot", "Roggenschrot".
    private static let coarseMealWords = ["schrot"]
    /// Seeds, kernels, flakes and nuts, in the three languages.
    private static let seedWords = ["saaten", "saat", "samen", "körner", "korner", "kerne", "kern", "sesam", "chia", "flocken", "hafer", "mohn", "hirse", "quinoa", "amaranth", "buchweizen", "nuss", "nüsse", "nusse", "mandel", "walnuss", "haselnuss",
                                    "seed", "kernel", "flake", "oat", "sesame", "poppy", "millet", "buckwheat", "nut", "almond", "walnut", "hazelnut",
                                    "graine", "pepin", "flocon", "avoine", "tournesol", "courge", "lin", "pavot", "millet", "sarrasin", "noix", "noisette", "amande"]
    /// Words that carry a seed word without being one ("Kernseife" is not
    /// in a bread, but "Zimt" is not a kernel either).
    private static let notSeedWords = ["hefe", "yeast", "levure", "malz", "malt", "butter", "beurre", "pulver", "powder", "poudre", "gewurz", "gewürz", "spice", "epice", "linsen", "lentil", "lentille"]
    /// Dark but not wholegrain flour counts half towards the heavy share.
    private static let darkFlourAshKey = 1050

    /// What the flours and seeds of `components` say the dough is; nil for a
    /// recipe without any flour. Rows that stand for another component
    /// (weight zero) and starters are left out; the starter's flour is the
    /// flour of the component it was made from.
    public static func doughType(for components: [DoughComposition.Component]) -> DoughType? {
        var flour = 0.0
        var heavy = 0.0
        var dark = 0.0
        var seeds = 0.0

        for ingredient in components.flatMap(\.ingredients) where ingredient.weight > 0 && ingredient.grams > 0 {
            let key = ingredient.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE")).lowercased()
            switch DoughComposition.classify(ingredient.name) {
            case .flour:
                flour += ingredient.grams
                let recognized = FlourSubstitution.recognize(ingredient.name)
                let isCoarse = coarseMealWords.contains(where: key.contains)
                if recognized?.grain == .rye || recognized?.isWholeGrain == true || isCoarse {
                    heavy += ingredient.grams
                } else if let recognized, recognized.milling.ashKey >= darkFlourAshKey {
                    dark += ingredient.grams
                }
            case .other:
                if seedWords.contains(where: key.contains), !notSeedWords.contains(where: key.contains) {
                    seeds += ingredient.grams
                }
            case .water, .starter:
                break
            }
        }

        guard flour > 0 else { return nil }
        let heavyShare = heavy / flour
        let seedShare = seeds / flour
        if heavyShare >= heavyFlourShareForRye || seedShare >= seedShareForRye {
            return .ryeWholeGrain
        }
        if (heavy + dark) / flour <= heavyFlourShareForLightWheat, seedShare < seedShareForLightWheat {
            return .lightWheat
        }
        return .mixed
    }
}
