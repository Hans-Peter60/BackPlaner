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
    /// names only: "Trockenhefe" is something else and stays apart.
    private static let synonyms: [String: String] = [
        "frischhefe": "hefe", "frische hefe": "hefe", "hefe frisch": "hefe", "backhefe": "hefe",
        "hefewurfel": "hefe", "hefe, frisch": "hefe",
        "fresh yeast": "yeast", "baker's yeast": "yeast", "bakers yeast": "yeast", "compressed yeast": "yeast",
        "levure fraiche": "levure", "levure de boulanger": "levure", "levure du boulanger": "levure",
        "levure boulangere": "levure", "levure boulangere fraiche": "levure",
        "eier": "ei", "huhnerei": "ei", "huhnereier": "ei", "vollei": "ei",
        "eggs": "egg", "whole egg": "egg", "whole eggs": "egg",
        "oeufs": "oeuf", "œuf": "oeuf", "œufs": "oeuf", "oeuf entier": "oeuf", "oeufs entiers": "oeuf",
    ]

    public static func comparisonKey(_ name: String) -> String {
        let key = displayName(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .localizedLowercase
        return synonyms[key] ?? key
    }
}
