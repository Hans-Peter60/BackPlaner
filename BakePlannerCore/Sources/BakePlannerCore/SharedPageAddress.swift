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
