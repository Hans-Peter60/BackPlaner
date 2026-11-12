import Foundation

public enum IngredientNameNormalizer {
    private static let temperatureExpressions: [NSRegularExpression] = [
        #"\([^)]*(?:°\s*[cf]|grad|celsius|fahrenheit|temperatur)[^)]*\)"#,
        // "Hefe (optional)" is yeast: a remark on whether to use it is no
        // part of the name, on the list or against the pantry.
        #"\(\s*(?:optional|wahlweise|nach belieben|nach geschmack|bei bedarf|facultatif|facultative|optionnel|optionnelle|au gout|au goût|to taste|if desired|if needed)\s*\)"#,
        #"[-+]?\d+(?:[,.]\d+)?\s*(?:°\s*[cf]?|grad(?:\s+(?:celsius|fahrenheit))?|celsius|fahrenheit)"#,
        #"\b(?:eiskalt|kalt|lauwarm|warm|heiß|heiss|zimmerwarm|zimmertemperiert|raumtemperiert)\p{L}*\b"#
    ].compactMap {
        try? NSRegularExpression(
            pattern: $0,
            options: [.caseInsensitive, .useUnicodeWordBoundaries]
        )
    }

    /// What a removed temperature leaves inside brackets: "Hefe ( )" from
    /// "Hefe (zimmerwarm)", "Ei (Größe M, )" from "Ei (Größe M, zimmerwarm)".
    /// Separators next to a bracket go, then brackets left empty.
    private static let bracketTidying: [(expression: NSRegularExpression?, template: String)] = [
        (try? NSRegularExpression(pattern: #"\(\s*[,;:\-]*\s*"#), "("),
        (try? NSRegularExpression(pattern: #"\s*[,;:\-]*\s*\)"#), ")"),
        (try? NSRegularExpression(pattern: #"\(\)"#), " ")
    ]

    private static let whitespaceExpression = try? NSRegularExpression(pattern: #"\s{2,}"#)

    public static func displayName(_ name: String) -> String {
        var result = name

        for expression in temperatureExpressions {
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: " "
            )
        }

        for (expression, template) in bracketTidying {
            guard let expression else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: template
            )
        }

        if let whitespaceExpression {
            let range = NSRange(result.startIndex..., in: result)
            result = whitespaceExpression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: " "
            )
        }

        let punctuation = CharacterSet(charactersIn: ",;:-")
        let cleanedName = result.trimmingCharacters(
            in: .whitespacesAndNewlines.union(punctuation)
        )

        return cleanedName.isEmpty
            ? name.trimmingCharacters(in: .whitespacesAndNewlines)
            : cleanedName
    }

    /// Names that mean the same thing when shopping and in the pantry, so
    /// "Frischhefe" lands on the "Hefe" item and "Eier" on "Ei". Whole
    /// names only, after the descriptors are gone: "Trockenhefe" is
    /// something else and stays apart.
    private static let synonyms: [String: String] = [
        "frischhefe": "hefe", "frische hefe": "hefe", "hefe frisch": "hefe", "backhefe": "hefe",
        "hefewurfel": "hefe", "hefe, frisch": "hefe",
        "fresh yeast": "yeast", "baker's yeast": "yeast", "bakers yeast": "yeast", "compressed yeast": "yeast",
        "levure fraiche": "levure", "levure de boulanger": "levure", "levure du boulanger": "levure",
        "levure boulangere": "levure", "levure boulangere fraiche": "levure",
        "eier": "ei", "huhnerei": "ei", "huhnereier": "ei", "vollei": "ei",
        "eggs": "egg", "whole egg": "egg", "whole eggs": "egg",
        "oeufs": "oeuf", "œuf": "oeuf", "œufs": "oeuf", "oeuf entier": "oeuf", "oeufs entiers": "oeuf",
        "instanthefe": "trockenhefe", "instant hefe": "trockenhefe", "levure instantanee": "levure seche",
        "vollmilch": "milch", "whole milk": "milk", "lait entier": "lait",
        "kristallzucker": "zucker", "feinzucker": "zucker", "haushaltszucker": "zucker", "feinkristallzucker": "zucker",
        "granulated sugar": "sugar", "caster sugar": "sugar", "sucre semoule": "sucre", "sucre en poudre": "sucre",
        "sesamsaat": "sesam", "sesamsamen": "sesam", "sesame seeds": "sesame", "graines de sesame": "sesame",
        "leinsaat": "leinsamen", "leinsamen geschrotet": "leinsamen", "flaxseed": "flaxseeds", "linseed": "flaxseeds", "linseeds": "flaxseeds",
        "sonnenblumensamen": "sonnenblumenkerne", "sunflower seed": "sunflower seeds", "graines de tournesol": "tournesol",
        "kurbissamen": "kurbiskerne", "pumpkin seed": "pumpkin seeds", "graines de courge": "courge",
        "walnusskerne": "walnusse", "walnuss": "walnusse", "walnut": "walnuts", "noix de grenoble": "noix",
        "haselnusskerne": "haselnusse", "haselnuss": "haselnusse", "hazelnut": "hazelnuts", "noisette": "noisettes",
        "mandelkerne": "mandeln", "mandel": "mandeln", "almond": "almonds", "amande": "amandes",
        "speisesalz": "salz", "meersalz": "salz", "steinsalz": "salz", "sea salt": "salt", "table salt": "salt", "sel de mer": "sel", "fleur de sel": "sel",
    ]

    /// Words that describe how an ingredient is used, not which one it is:
    /// "Walnüsse, gehackt" are the walnuts in the pantry, "zarte Haferflocken"
    /// the oat flakes. Compared without them.
    private static let descriptors: Set<String> = [
        "frisch", "frische", "frischer", "frisches", "zart", "zarte", "kernig", "kernige", "ganz", "ganze",
        "gehackt", "gehackte", "gerostet", "gerostete", "geschrotet", "geschrotete", "weich", "weiche",
        "zerlassen", "zerlassene", "geschmolzen", "geschmolzene", "flussig", "flussige", "gewurfelt", "gewurfelte",
        "fein", "feine", "feiner", "grob", "grobe", "ungesalzen", "ungesalzene", "gesiebt", "gesiebte",
        "bio", "ca", "etwa", "evtl",
        "fresh", "chopped", "toasted", "roasted", "melted", "softened", "whole", "fine", "coarse", "unsalted", "sifted", "organic",
        "frais", "fraiche", "fraiches", "hache", "hachee", "hachees", "haches", "grille", "grillee", "grillees", "grilles",
        "fondu", "fondue", "entier", "entiere", "entiers", "entieres", "fin", "fine", "fins", "fines", "tamise", "tamisee",
    ]

    /// Grains whose wholemeal flour is written three ways:
    /// "Weizenvollkornmehl", "Vollkornweizenmehl", "Weizenmehl Vollkorn".
    private static let grains = ["weizen", "roggen", "dinkel", "emmer", "einkorn", "kamut", "hafer", "gerste"]

    /// The display name folded for comparison, brackets and all: case- and
    /// accent-insensitive, nothing else changed. For callers that read the
    /// name's structure themselves (ComponentProductMatcher cuts at the
    /// first bracket or slash).
    public static func foldedName(_ name: String) -> String {
        displayName(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .localizedLowercase
    }

    /// The name as the shopping list and the pantry compare it: folded,
    /// without descriptors, flour types and wholemeal spellings unified,
    /// synonyms resolved.
    public static func comparisonKey(_ name: String) -> String {
        let folded = foldedName(name)
        var tokens = folded
            .split { $0 == " " || $0 == "," || $0 == ";" || $0 == "." || $0 == "(" || $0 == ")" }
            .map(String.init)
            .filter { !descriptors.contains($0) }
        // Flour types: "Type 550", "Typ 550" and "T550" are "550". A French
        // "T65" keeps its T — the French types end at T170, the German ones
        // start at 405, so the number tells them apart.
        tokens = tokens.compactMap { token in
            if token == "type" || token == "typ" { return nil }
            if token.hasPrefix("t"), let number = Int(token.dropFirst()), number >= 400 { return String(number) }
            return token
        }
        // "Weizenmehl Vollkorn" and "Vollkornweizenmehl" are "Weizenvollkornmehl".
        if let index = tokens.firstIndex(of: "vollkorn"),
           let flour = tokens.firstIndex(where: { token in grains.contains { token == $0 + "mehl" } }) {
            tokens[flour] = String(tokens[flour].dropLast(4)) + "vollkornmehl"
            tokens.remove(at: index)
        }
        tokens = tokens.map { token in
            for grain in grains where token == "vollkorn" + grain + "mehl" {
                return grain + "vollkornmehl"
            }
            return token
        }
        let key = tokens.joined(separator: " ")
        return synonyms[key] ?? key
    }
}
