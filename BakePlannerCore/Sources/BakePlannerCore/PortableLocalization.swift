//
//  PortableLocalization.swift
//  BakePlannerCore
//
//  On Apple platforms the package's texts come from the app's catalog
//  through Foundation's String(localized:bundle:locale:comment:). Foundation
//  elsewhere (Android) has no such initializer. There this file stands in
//  for it, so the same call sites compile: the text is looked up through
//  `CoreLocalization.lookup` — by default in the app's catalog as generated
//  into the package — and stays German where it has no translation. Nothing
//  here changes what the iOS app shows.
//

import Foundation

public enum CoreLocalization {
    /// The translation of a catalog key — the German text with `%@` and
    /// `%lld` where values go, as the app's catalog keys it — or `nil` to keep
    /// the German text. Only consulted where Foundation cannot localize.
    /// Answers from the app's catalog as generated into the package
    /// (PackageTranslations), in the language the app shows.
    public static var lookup: (String) -> String? = { key in
        translation(of: key, language: languageCode)
    }

    /// The text for `key` in `language` ("en", "fr"), from the app's catalog.
    static func translation(of key: String, language: String) -> String? {
        PackageTranslations.table[key]?[language]
    }

    /// The language the app shows: the one picked in Settings, else the
    /// system's, without its region.
    static var languageCode: String {
        let stored = AppSettings.storedLanguage
        return RecipeFB.baseLanguageCode(from: stored.isEmpty ? Locale.current.identifier : stored)
    }

    /// `format` with its placeholders (`%@`, `%lld`, `%d`, `%lf`, also
    /// numbered like `%2$@`) replaced by `arguments` in order, and `%%` as
    /// `%`. The values arrive already written out, so the placeholders'
    /// kinds only mark where they go.
    static func fill(_ format: String, with arguments: [String]) -> String {
        var result = ""
        var next = 0
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else {
                result.append(format[index])
                index = format.index(after: index)
                continue
            }
            var cursor = format.index(after: index)
            if cursor < format.endIndex, format[cursor] == "%" {
                result.append("%")
                index = format.index(after: cursor)
                continue
            }
            var digits = ""
            while cursor < format.endIndex, format[cursor].isNumber {
                digits.append(format[cursor])
                cursor = format.index(after: cursor)
            }
            var position: Int?
            if cursor < format.endIndex, format[cursor] == "$", let number = Int(digits) {
                position = number - 1
                cursor = format.index(after: cursor)
            }
            while cursor < format.endIndex, "lhqzjt".contains(format[cursor]) {
                cursor = format.index(after: cursor)
            }
            guard cursor < format.endIndex else {
                result.append(contentsOf: format[index...])
                break
            }
            let argument = position ?? next
            if position == nil { next += 1 }
            if arguments.indices.contains(argument) {
                result.append(arguments[argument])
            }
            index = format.index(after: cursor)
        }
        return result
    }
}

#if !canImport(Darwin)
/// A text with values in it, keyed the way the app's catalog keys it:
/// "„\(name)“" becomes the key "„%@“" with `name` as its value.
public struct PortableLocalizationValue: ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]

    public init(stringLiteral value: String) {
        key = value
        arguments = []
    }

    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []

        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ literal: String) {
            key += literal
        }

        public mutating func appendInterpolation(_ value: String) {
            key += "%@"
            arguments.append(value)
        }

        public mutating func appendInterpolation(_ value: Int) {
            key += "%lld"
            arguments.append(String(value))
        }

        public mutating func appendInterpolation<Value>(_ value: Value) {
            key += "%@"
            arguments.append(String(describing: value))
        }
    }
}

extension String {
    /// Stands in for Foundation's String(localized:bundle:locale:comment:)
    /// where Foundation has none; `bundle`, `locale` and `comment` are
    /// accepted for the same call sites and not used.
    init(localized value: PortableLocalizationValue, bundle: Bundle? = nil,
         locale: Locale = Locale.current, comment: StaticString? = nil) {
        let format = CoreLocalization.lookup(value.key) ?? value.key
        self = CoreLocalization.fill(format, with: value.arguments)
    }
}
#endif
