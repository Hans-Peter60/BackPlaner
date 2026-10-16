//
//  BakingGlossary.swift
//  BackPlaner
//
//  Baker's terms that machine translation gets wrong — "Brühstück" came back
//  as "Breakfast" — and a plan that carries them through a translation
//  round untouched.
//

import Foundation

/// The baker's vocabulary in the app's languages.
///
/// A term is matched as a whole word in the text's language and written out
/// in the target language's canonical form. Only whole words: "Roggensauerteig"
/// is left to the translator, which handles such compounds well enough; it is
/// the bare technical nouns it has no idea about.
enum BakingGlossary {

    /// The forms of one term in one language: the first singular form is the
    /// one written out, every form is recognised.
    struct Forms {
        let singular: [String]
        let plural: [String]

        init(_ singular: [String], plural: [String] = []) {
            self.singular = singular
            self.plural = plural
        }
    }

    struct Term {
        /// Language code → forms. A language without an entry is not matched
        /// and not written; the translator is left to it.
        let forms: [String: Forms]
    }

    /// A term found in a text.
    struct Match {
        let range: Range<String.Index>
        let term: Term
        let isPlural: Bool
    }

    /// The base terms and the grain compounds built from them.
    static let terms: [Term] = baseTerms + compoundTerms

    private static let baseTerms: [Term] = [
        // Pre-doughs and soakers, the component names most often mangled.
        Term(forms: ["de": Forms(["Brühstück"], plural: ["Brühstücke"]),
                     "en": Forms(["scald", "hot soaker"], plural: ["scalds"]),
                     "fr": Forms(["Graines ébouillantées"], plural: ["Graines ébouillantées"])]),
        Term(forms: ["de": Forms(["Quellstück"], plural: ["Quellstücke"]),
                     "en": Forms(["soaker"], plural: ["soakers"]),
                     "fr": Forms(["trempage"], plural: ["trempages"])]),
        Term(forms: ["de": Forms(["Kochstück"], plural: ["Kochstücke"]),
                     "en": Forms(["cooked soaker", "tangzhong", "water roux"], plural: ["cooked soakers"]),
                     "fr": Forms(["empois", "tangzhong"])]),
        Term(forms: ["de": Forms(["Anstellgut", "ASG"]),
                     "en": Forms(["sourdough starter", "starter"], plural: ["sourdough starters"]),
                     "fr": Forms(["levain chef", "levain-chef"], plural: ["levains chefs"])]),
        Term(forms: ["de": Forms(["Sauerteig"], plural: ["Sauerteige"]),
                     "en": Forms(["sourdough"], plural: ["sourdoughs"]),
                     "fr": Forms(["levain"], plural: ["levains"])]),
        Term(forms: ["de": Forms(["Vorteig"], plural: ["Vorteige"]),
                     "en": Forms(["preferment", "pre-ferment", "pre-dough"], plural: ["preferments"]),
                     "fr": Forms(["pré-ferment", "préferment"], plural: ["pré-ferments"])]),
        Term(forms: ["de": Forms(["Hauptteig"], plural: ["Hauptteige"]),
                     "en": Forms(["main dough", "final dough"], plural: ["main doughs"]),
                     "fr": Forms(["pâte principale", "pâte finale"], plural: ["pâtes principales"])]),
        Term(forms: ["de": Forms(["Pâte fermentée", "alter Teig"]),
                     "en": Forms(["pâte fermentée", "old dough"]),
                     "fr": Forms(["pâte fermentée"])]),
        Term(forms: ["de": Forms(["Poolish"]), "en": Forms(["poolish"]), "fr": Forms(["poolish"])]),
        Term(forms: ["de": Forms(["Biga"]), "en": Forms(["biga"]), "fr": Forms(["biga"])]),
        Term(forms: ["de": Forms(["Lievito Madre"]), "en": Forms(["lievito madre"]), "fr": Forms(["lievito madre"])]),

        // Process words from the instructions.
        Term(forms: ["de": Forms(["Stockgare"]),
                     "en": Forms(["bulk fermentation", "bulk proof"]),
                     "fr": Forms(["pointage"])]),
        Term(forms: ["de": Forms(["Stückgare"]),
                     "en": Forms(["final proof", "final proofing"]),
                     "fr": Forms(["apprêt"])]),
        Term(forms: ["de": Forms(["Schüttwasser"]),
                     "en": Forms(["mixing water"]),
                     "fr": Forms(["eau de coulage"])]),
        Term(forms: ["de": Forms(["Gärkorb", "Gärkörbchen"], plural: ["Gärkörbe"]),
                     "en": Forms(["banneton", "proofing basket"], plural: ["bannetons", "proofing baskets"]),
                     "fr": Forms(["banneton"], plural: ["bannetons"])]),
        Term(forms: ["de": Forms(["Teigling"], plural: ["Teiglinge"]),
                     "en": Forms(["dough piece"], plural: ["dough pieces"]),
                     "fr": Forms(["pâton"], plural: ["pâtons"])]),
        Term(forms: ["de": Forms(["Ofentrieb"]),
                     "en": Forms(["oven spring"]),
                     "fr": Forms(["poussée au four"])]),
        Term(forms: ["de": Forms(["Altbrot", "Restbrot"]),
                     "en": Forms(["old bread", "stale bread"]),
                     "fr": Forms(["pain rassis"])]),
        Term(forms: ["de": Forms(["Krume"]),
                     "en": Forms(["crumb"]),
                     "fr": Forms(["mie"])]),
        Term(forms: ["de": Forms(["Fensterprobe"]),
                     "en": Forms(["windowpane test"]),
                     "fr": Forms(["test de la membrane"])]),
        Term(forms: ["de": Forms(["Sauerteigstufe"], plural: ["Sauerteigstufen"]),
                     "en": Forms(["sourdough stage"], plural: ["sourdough stages"]),
                     "fr": Forms(["étape de levain"], plural: ["étapes de levain"])])
    ]

    // MARK: - Grain compounds

    /// German writes the grain into the word: "Weizenanstellgut",
    /// "Roggensauerteig". Those are not whole words to the matcher, and the
    /// translator made "wheat animal feed" of the first. So every grain gets
    /// its own term for the starter, the sourdough and the preferment, in
    /// both directions.
    private struct Grain {
        let de: String
        let en: String
        /// "de blé", "d'épeautre" — or an adjective, "complet".
        let fr: String
        let frIsAdjective: Bool
        /// The bare French noun, "blé", for "blé concassé"; nil for the
        /// adjective entry.
        var frNoun: String? = nil
    }

    private static let grains: [Grain] = [
        Grain(de: "Weizen",     en: "wheat",      fr: "de blé",         frIsAdjective: false, frNoun: "blé"),
        Grain(de: "Roggen",     en: "rye",        fr: "de seigle",      frIsAdjective: false, frNoun: "seigle"),
        Grain(de: "Dinkel",     en: "spelt",      fr: "d'épeautre",     frIsAdjective: false, frNoun: "épeautre"),
        Grain(de: "Emmer",      en: "emmer",      fr: "d'amidonnier",   frIsAdjective: false, frNoun: "amidonnier"),
        Grain(de: "Einkorn",    en: "einkorn",    fr: "d'engrain",      frIsAdjective: false, frNoun: "engrain"),
        Grain(de: "Hartweizen", en: "durum",      fr: "de blé dur",     frIsAdjective: false, frNoun: "blé dur"),
        Grain(de: "Vollkorn",   en: "wholegrain", fr: "complet",        frIsAdjective: true)
    ]

    /// Flours, meals and semolina per grain: "Roggenmehl 1370" came back
    /// as "farine de blé 1370" — wheat instead of rye. The type number
    /// after the word is left alone and travels with it.
    private static let flourTerms: [Term] = grains.compactMap { grain -> [Term]? in
        guard let noun = grain.frNoun else { return nil }
        return [
            // Roggenmehl → rye flour → farine de seigle
            Term(forms: ["de": Forms(["\(grain.de)mehl", "\(grain.de)-Mehl"]),
                         "en": Forms(["\(grain.en) flour"]),
                         "fr": Forms(["farine \(grain.fr)"])]),
            // Weizenvollkornmehl → whole wheat flour → farine de blé complète
            Term(forms: ["de": Forms(["\(grain.de)vollkornmehl", "\(grain.de)-Vollkornmehl"]),
                         "en": Forms(["whole \(grain.en) flour", "wholegrain \(grain.en) flour", "whole-\(grain.en) flour"]),
                         "fr": Forms(["farine \(grain.fr) complète", "farine complète \(grain.fr)"])]),
            // Roggenschrot → rye meal → seigle concassé
            Term(forms: ["de": Forms(["\(grain.de)schrot", "\(grain.de)-Schrot"]),
                         "en": Forms(["\(grain.en) meal", "cracked \(grain.en)"]),
                         "fr": Forms(["\(noun) concassé"])])
        ]
    }.flatMap { $0 } + [
        // Not the bare "Mehl": in English "flour" is also the verb ("flour
        // the banneton"), and the translator handles the plain noun itself.
        Term(forms: ["de": Forms(["Vollkornmehl"]),
                     "en": Forms(["wholegrain flour", "wholemeal flour", "whole grain flour"]),
                     "fr": Forms(["farine complète"])]),
        Term(forms: ["de": Forms(["Hartweizengrieß", "Hartweizengriess"]),
                     "en": Forms(["durum semolina", "durum wheat semolina", "semolina"]),
                     "fr": Forms(["semoule de blé dur", "semoule"])])
    ]

    private static let compoundTerms: [Term] = flourTerms + grains.flatMap { grain in
        [
            // Weizenanstellgut → wheat sourdough starter → levain chef de blé
            Term(forms: ["de": Forms(["\(grain.de)anstellgut", "\(grain.de)-Anstellgut"]),
                         "en": Forms(["\(grain.en) sourdough starter", "\(grain.en) starter"]),
                         "fr": Forms(["levain chef \(grain.fr)", "levain-chef \(grain.fr)"])]),
            // Roggensauerteig → rye sourdough → levain de seigle
            Term(forms: ["de": Forms(["\(grain.de)sauerteig", "\(grain.de)-Sauerteig"], plural: ["\(grain.de)sauerteige"]),
                         "en": Forms(["\(grain.en) sourdough"], plural: ["\(grain.en) sourdoughs"]),
                         "fr": Forms(["levain \(grain.fr)"], plural: ["levains \(grain.fr)"])]),
            // Weizenvorteig → wheat preferment → pré-ferment de blé
            Term(forms: ["de": Forms(["\(grain.de)vorteig", "\(grain.de)-Vorteig"]),
                         "en": Forms(["\(grain.en) preferment", "\(grain.en) pre-ferment"]),
                         "fr": Forms(["pré-ferment \(grain.fr)"])])
        ]
    }

    /// Every term found in `text`, written in `language`, left to right and
    /// without overlaps. Longer forms win over shorter ones, so "sourdough
    /// starter" is the starter and not a sourdough followed by a word.
    static func matches(in text: String, language: String) -> [Match] {
        struct Candidate {
            let form: String
            let term: Term
            let isPlural: Bool
        }

        var candidates = [Candidate]()
        for term in terms {
            guard let forms = term.forms[language] else { continue }
            candidates += forms.singular.map { Candidate(form: $0, term: term, isPlural: false) }
            candidates += forms.plural.map { Candidate(form: $0, term: term, isPlural: true) }
        }
        candidates.sort { $0.form.count > $1.form.count }

        var found = [Match]()
        for candidate in candidates {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: candidate.form,
                                         options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchRange) {
                searchRange = range.upperBound..<text.endIndex
                guard isWholeWord(range, in: text) else { continue }
                guard !found.contains(where: { $0.range.overlaps(range) }) else { continue }
                found.append(Match(range: range, term: candidate.term, isPlural: candidate.isPlural))
            }
        }

        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// The term written in `language`, or nil when the glossary has no word
    /// for it there. Capitalised when asked, i.e. at the start of a sentence;
    /// German nouns are stored capitalised already.
    static func rendering(of match: Match, in language: String, capitalized: Bool) -> String? {
        guard let forms = match.term.forms[language] else { return nil }
        guard let word = (match.isPlural ? forms.plural.first : nil) ?? forms.singular.first else { return nil }
        guard capitalized, let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }

    /// True when the term is written in both languages, so protecting it is
    /// worth anything at all.
    static func canTranslate(_ match: Match, into language: String) -> Bool {
        match.term.forms[language] != nil
    }

    /// Whether a translation uses the glossary's words for every term in its
    /// source text. False for a translation made before the glossary
    /// existed — "Breakfast" for "Brühstück" — which is then due for a new
    /// round. A source text without terms passes.
    static func translationHonoursGlossary(sourceText: String, translation: String, from source: String, into target: String) -> Bool {
        let comparableTranslation = comparable(translation)

        for match in matches(in: sourceText, language: source) {
            guard let word = rendering(of: match, in: target, capitalized: false) else { continue }
            if !comparableTranslation.contains(comparable(word)) { return false }
        }
        return true
    }

    private static func comparable(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
    }

    private static func isWholeWord(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if before.isLetter || before.isNumber { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if after.isLetter || after.isNumber { return false }
        }
        return true
    }
}

/// Carries glossary terms through one round of machine translation.
///
/// For every text the plan decides what the translator gets to see:
///
/// - A text that *is* a term ("Brühstück") is not sent at all; the glossary
///   answers it.
/// - A text containing terms is sent with each term replaced by a numbered
///   placeholder ("[[1]]"), which the translator passes through and may move
///   to where the target language wants the word. Should a placeholder not
///   survive the round, the same text is also sent in pieces — the words
///   between the terms — and reassembled around the glossary's words. That
///   is poorer for a sentence, but never "Breakfast".
/// - Any other text goes through unchanged.
///
/// Build it, send `sourceTexts` in order, hand the translated texts back to
/// `results(translated:)` and get one result per input text.
struct GlossaryTranslationPlan {

    /// One text's way through the round.
    private enum Item {
        case unchanged(String)
        case term(String)
        case direct(request: Int)
        case protected(request: Int, placeholders: [String], pieces: [Piece])
    }

    /// Part of the fallback assembly: a translated piece, a term, or literal
    /// text (punctuation and spaces, which need no translating).
    private enum Piece {
        case request(index: Int, leading: String, trailing: String)
        case literal(String)
        case term(String)
    }

    private let items: [Item]

    /// The texts to send to the translator, in request order.
    private(set) var sourceTexts: [String] = []

    /// The placeholder that stands in for the n-th term of a text.
    static func placeholder(_ number: Int) -> String { "[[\(number)]]" }

    /// Anything a translator may have made of a placeholder: lost or doubled
    /// brackets, spaces slipped in.
    private static let placeholderPattern = try? NSRegularExpression(pattern: #"(?:\[\s*)+(\d+)(?:\s*\])+"#)

    /// The glossary's word for a text that is nothing but a term ("Brühstück"
    /// → "Scald"), nil for any other text. Needs no translator, so a cached
    /// translation can be corrected with it as well.
    static func termTranslation(of text: String, from source: String, into target: String) -> String? {
        let matches = BakingGlossary.matches(in: text, language: source)
            .filter { BakingGlossary.canTranslate($0, into: target) }
        return termTranslation(of: text, matches: matches, into: target)
    }

    private static func termTranslation(of text: String, matches: [BakingGlossary.Match], into target: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches.count == 1, String(text[matches[0].range]) == trimmed else { return nil }
        return BakingGlossary.rendering(of: matches[0], in: target, capitalized: startsUppercase(trimmed))
    }

    init(texts: [String], from source: String, into target: String) {
        var items = [Item]()
        var requests = [String]()

        for text in texts {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                items.append(.unchanged(text))
                continue
            }

            let matches = BakingGlossary.matches(in: text, language: source)
                .filter { BakingGlossary.canTranslate($0, into: target) }

            guard !matches.isEmpty else {
                requests.append(text)
                items.append(.direct(request: requests.count - 1))
                continue
            }

            // The whole text is one term: no translation needed.
            if let word = Self.termTranslation(of: text, matches: matches, into: target) {
                items.append(.term(word))
                continue
            }

            // Placeholder version first, its pieces for the fallback after it.
            let protectedIndex = requests.count
            requests.append("")

            var protectedText = ""
            var placeholders = [String]()
            var pieces = [Piece]()
            var cursor = text.startIndex

            for (number, match) in matches.enumerated() {
                let word = BakingGlossary.rendering(of: match, in: target, capitalized: false) ?? String(text[match.range])
                let between = String(text[cursor..<match.range.lowerBound])

                protectedText += between + Self.placeholder(number + 1)
                placeholders.append(word)
                pieces += Self.pieces(for: between, requests: &requests)
                pieces.append(.term(word))
                cursor = match.range.upperBound
            }
            let tail = String(text[cursor...])
            protectedText += tail
            pieces += Self.pieces(for: tail, requests: &requests)

            requests[protectedIndex] = protectedText
            items.append(.protected(request: protectedIndex, placeholders: placeholders, pieces: pieces))
        }

        self.items = items
        self.sourceTexts = requests
    }

    /// One result per input text, in input order. `translated` are the
    /// translations of `sourceTexts`, in that order; a shorter list leaves
    /// the texts beyond it as they were.
    func results(translated: [String]) -> [String] {
        func translation(_ index: Int) -> String? {
            index < translated.count ? translated[index] : nil
        }

        return items.map { item in
            switch item {
            case .unchanged(let text):
                return text
            case .term(let word):
                return word
            case .direct(let request):
                return translation(request) ?? sourceTexts[request]
            case .protected(let request, let placeholders, let pieces):
                if let output = translation(request),
                   let restored = Self.restore(output, placeholders: placeholders) {
                    return restored
                }
                return Self.assemble(pieces, translation: translation)
            }
        }
    }

    // MARK: - Pieces for the fallback

    private static func pieces(for text: String, requests: inout [String]) -> [Piece] {
        guard !text.isEmpty else { return [] }
        guard text.contains(where: \.isLetter) else { return [.literal(text)] }

        let leading = String(text.prefix(while: \.isWhitespace))
        let trailing = String(text.reversed().prefix(while: \.isWhitespace).reversed())
        let core = text.trimmingCharacters(in: .whitespacesAndNewlines)

        requests.append(core)
        return [.request(index: requests.count - 1, leading: leading, trailing: trailing)]
    }

    private static func assemble(_ pieces: [Piece], translation: (Int) -> String?) -> String {
        var result = ""
        for piece in pieces {
            switch piece {
            case .literal(let text):
                result += text
            case .term(let word):
                // A term that opens the text starts the sentence.
                let atStart = result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                result += atStart ? capitalizingFirst(word) : word
            case .request(let index, let leading, let trailing):
                let translated = translation(index)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                result += leading + translated + trailing
            }
        }
        return result
    }

    // MARK: - Restoring placeholders

    /// The output with every placeholder replaced by its term, or nil when
    /// the translator lost, doubled or renumbered one.
    private static func restore(_ output: String, placeholders: [String]) -> String? {
        guard let pattern = placeholderPattern else { return nil }

        let fullRange = NSRange(output.startIndex..., in: output)
        let found = pattern.matches(in: output, range: fullRange)

        var numbers = [Int]()
        for match in found {
            guard let numberRange = Range(match.range(at: 1), in: output),
                  let number = Int(output[numberRange]) else { return nil }
            numbers.append(number)
        }
        guard numbers.sorted() == Array(1...placeholders.count) else { return nil }

        var result = output
        for match in found.reversed() {
            guard let range = Range(match.range, in: result),
                  let numberRange = Range(match.range(at: 1), in: output),
                  let number = Int(output[numberRange]) else { return nil }

            let atStart = result[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let word = placeholders[number - 1]
            result.replaceSubrange(range, with: atStart ? capitalizingFirst(word) : word)
        }
        return result
    }

    private static func capitalizingFirst(_ word: String) -> String {
        guard let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }

    private static func startsUppercase(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return first.isUppercase
    }
}
