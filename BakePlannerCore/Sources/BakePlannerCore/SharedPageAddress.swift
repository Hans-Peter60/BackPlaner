//
//  SharedPageAddress.swift
//  BakePlannerCore
//
//  The page address in what a browser shares. Safari's share extension
//  hands the iPhone a URL; Android's share sheet hands over text — Chrome
//  sends the address alone, other browsers put the page title in front of
//  it or a line break after it.
//

import Foundation

/// What a shared text is for the import: the address of a page for the web
/// import, or recipe text — a selection shared from the browser — for the
/// text import.
public enum SharedRecipeText {
    public enum Kind: Equatable {
        case page(URL)
        case text(String)
    }

    /// Text this long is a recipe even when it carries an address: a
    /// selection shared with the page's link appended.
    public static let textWithAddressCharacters = 200

    /// How the shared text is to be imported, or nil when it is neither an
    /// address nor enough text for a recipe.
    public static func kind(of text: String) -> Kind? {
        let cleaned = PastedRecipeText.normalized(text)
        if let url = SharedPageAddress.url(in: cleaned) {
            let withoutAddress = cleaned.replacingOccurrences(of: url.absoluteString, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return withoutAddress.count >= textWithAddressCharacters ? .text(cleaned) : .page(url)
        }
        return cleaned.count >= PastedRecipeText.minimumCharacters ? .text(cleaned) : nil
    }
}

public enum SharedPageAddress {

    /// The first web address in `text`, or nil when there is none. Trailing
    /// punctuation a sentence may add is left off.
    public static func url(in text: String) -> URL? {
        for word in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let lowered = word.lowercased()
            guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { continue }
            var candidate = String(word)
            while let last = candidate.last, ".,;:!?)\"'".contains(last) {
                candidate.removeLast()
            }
            if let url = URL(string: candidate), url.host != nil {
                return url
            }
        }
        return nil
    }
}
