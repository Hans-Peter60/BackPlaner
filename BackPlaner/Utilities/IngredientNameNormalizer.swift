import Foundation

enum IngredientNameNormalizer {
    private static let temperatureExpressions: [NSRegularExpression] = [
        #"\([^)]*(?:°\s*[cf]|grad|celsius|fahrenheit|temperatur)[^)]*\)"#,
        #"[-+]?\d+(?:[,.]\d+)?\s*(?:°\s*[cf]?|grad(?:\s+(?:celsius|fahrenheit))?|celsius|fahrenheit)"#,
        #"\b(?:eiskalt|kalt|lauwarm|warm|heiß|heiss|zimmerwarm|zimmertemperiert|raumtemperiert)\p{L}*\b"#
    ].compactMap {
        try? NSRegularExpression(
            pattern: $0,
            options: [.caseInsensitive, .useUnicodeWordBoundaries]
        )
    }

    private static let whitespaceExpression = try? NSRegularExpression(pattern: #"\s{2,}"#)

    static func displayName(_ name: String) -> String {
        var result = name

        for expression in temperatureExpressions {
            let range = NSRange(result.startIndex..., in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: " "
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

    static func comparisonKey(_ name: String) -> String {
        displayName(name)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .localizedLowercase
    }
}
