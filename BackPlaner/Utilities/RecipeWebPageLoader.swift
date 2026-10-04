import Foundation
import UIKit

/// A recipe as a web page declares it in its schema.org markup (JSON-LD).
/// Most recipe sites and all common WordPress recipe plug-ins emit it, so it
/// is the most reliable source the page offers.
struct StructuredWebRecipe: Sendable, Equatable {
    var name = ""
    var summary = ""
    /// BCP-47 language of the recipe text, if the page declares one.
    var language = ""
    var imageURL: URL?
    /// Ingredient lines as printed, for example "500 g Weizenmehl 550".
    var ingredientLines: [String] = []
    var instructionSections: [StructuredInstructionSection] = []
    var prepMinutes = 0
    var cookMinutes = 0
    var totalMinutes = 0
    var keywords: [String] = []
    var yield = ""

    var hasRecipeData: Bool {
        !ingredientLines.isEmpty || instructionSections.contains { !$0.steps.isEmpty }
    }
}

struct StructuredInstructionSection: Sendable, Equatable {
    var name = ""
    var steps: [String] = []
}

/// What the loader found on a page: the structured recipe when the page
/// has one, plus the readable text for the AI stages.
struct RecipeWebPage: Sendable {
    let url: URL
    let title: String
    let language: String
    let structuredRecipe: StructuredWebRecipe?
    let readableText: String
    let imageURL: URL?

    /// The text handed to the AI stages: the structured data first, since it
    /// is clean, then the page text, which still carries the component
    /// headings and remarks the structured data drops.
    var analysisText: String {
        var sections: [String] = []
        if let structuredRecipe {
            sections.append(Self.describe(structuredRecipe))
        }
        let remaining = max(8_000, RecipeWebPageLoader.maximumAnalysisCharacters - sections.joined().count)
        if !readableText.isEmpty {
            sections.append("SEITENTEXT:\n" + String(readableText.prefix(remaining)))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func describe(_ recipe: StructuredWebRecipe) -> String {
        var lines = ["STRUKTURIERTE REZEPTDATEN (schema.org):"]
        if !recipe.name.isEmpty { lines.append("Titel: \(recipe.name)") }
        if !recipe.summary.isEmpty { lines.append("Beschreibung: \(recipe.summary)") }
        if !recipe.language.isEmpty { lines.append("Sprache: \(recipe.language)") }
        if !recipe.yield.isEmpty { lines.append("Menge: \(recipe.yield)") }
        if recipe.prepMinutes > 0 { lines.append("Vorbereitungszeit: \(recipe.prepMinutes) Minuten") }
        if recipe.cookMinutes > 0 { lines.append("Back-/Garzeit: \(recipe.cookMinutes) Minuten") }
        if recipe.totalMinutes > 0 { lines.append("Gesamtzeit: \(recipe.totalMinutes) Minuten") }
        if !recipe.ingredientLines.isEmpty {
            lines.append("ZUTATEN:")
            lines.append(contentsOf: recipe.ingredientLines.map { "- \($0)" })
        }
        if recipe.instructionSections.contains(where: { !$0.steps.isEmpty }) {
            lines.append("ZUBEREITUNG:")
            for section in recipe.instructionSections {
                if !section.name.isEmpty { lines.append("[\(section.name)]") }
                for (index, step) in section.steps.enumerated() {
                    lines.append("\(index + 1). \(step)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum RecipeWebImportError: LocalizedError {
    case invalidAddress
    case pageUnavailable(statusCode: Int?)
    case notAWebPage
    case noRecipeFound

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return String(localized: "Die Adresse ist keine gültige Internetadresse. Sie muss mit https:// beginnen oder einen Domainnamen enthalten.", bundle: AppSettings.localizationBundle)
        case .pageUnavailable(let statusCode):
            if let statusCode {
                return String(localized: "Die Seite konnte nicht geladen werden (Fehler \(statusCode)). Manche Seiten verlangen eine Anmeldung oder sperren den Abruf.", bundle: AppSettings.localizationBundle)
            }
            return String(localized: "Die Seite konnte nicht geladen werden. Bitte prüfe die Adresse und die Internetverbindung.", bundle: AppSettings.localizationBundle)
        case .notAWebPage:
            return String(localized: "Unter dieser Adresse liegt keine Internetseite, sondern zum Beispiel eine PDF- oder Bilddatei.", bundle: AppSettings.localizationBundle)
        case .noRecipeFound:
            return String(localized: "Auf der Seite wurde kein Rezept mit Zutaten und Arbeitsschritten gefunden.", bundle: AppSettings.localizationBundle)
        }
    }
}

/// Fetches a recipe page and extracts what the import needs from it. The
/// page is loaded on the device, so the address never reaches the server;
/// only the extracted text does, and only when the user chose the cloud.
enum RecipeWebPageLoader {

    static let maximumAnalysisCharacters = 50_000
    private static let maximumPageBytes = 6 * 1_024 * 1_024
    private static let maximumReadableCharacters = 40_000
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1 BackPlaner"

    /// Turns what the user typed or pasted into an https address. A bare
    /// domain is accepted; http is upgraded, since App Transport Security
    /// would reject it anyway.
    static func normalizedURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.lowercased().hasPrefix("http://") {
            text = "https://" + text.dropFirst("http://".count)
        } else if !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        guard let url = URL(string: text),
              let host = url.host(), host.contains("."),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    static func load(_ url: URL) async throws -> RecipeWebPage {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("de-DE,de;q=0.9,en;q=0.7,fr;q=0.6", forHTTPHeaderField: "Accept-Language")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            AppLog.data.warning("Recipe web import: page load failed: \(error.localizedDescription)")
            throw RecipeWebImportError.pageUnavailable(statusCode: nil)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RecipeWebImportError.pageUnavailable(statusCode: http.statusCode)
        }
        if let mimeType = response.mimeType?.lowercased(),
           !mimeType.contains("html"), !mimeType.contains("xml"), !mimeType.hasPrefix("text/") {
            throw RecipeWebImportError.notAWebPage
        }
        guard data.count <= maximumPageBytes else {
            throw RecipeWebImportError.notAWebPage
        }

        let html = decodeHTML(data, declaredEncodingName: response.textEncodingName)
        let page = parse(html: html, url: response.url ?? url)
        guard page.structuredRecipe?.hasRecipeData == true
                || page.readableText.count >= 200 else {
            throw RecipeWebImportError.noRecipeFound
        }
        return page
    }

    /// Downloads the page's recipe photo, if it offers one that is usable.
    static func loadImage(from url: URL?) async -> UIImage? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              data.count <= 12 * 1_024 * 1_024,
              let image = UIImage(data: data),
              image.size.width >= 120, image.size.height >= 120 else {
            return nil
        }
        return image
    }

    // MARK: - Parsing

    /// Everything after the download, separated so it can be tested on
    /// fixture pages without a network.
    static func parse(html: String, url: URL) -> RecipeWebPage {
        let structured = structuredRecipes(in: html, baseURL: url)
            .max { scoreOf($0) < scoreOf($1) }
        let readable = readableText(from: html)
        let title = structured?.name.nonEmpty
            ?? metaContent(property: "og:title", in: html)
            ?? htmlTitle(in: html)
            ?? ""
        let language = structured?.language.nonEmpty
            ?? htmlLanguage(in: html)
            ?? ""
        let imageURL = structured?.imageURL
            ?? metaContent(property: "og:image", in: html).flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
        return RecipeWebPage(
            url: url,
            title: title,
            language: language,
            structuredRecipe: structured?.hasRecipeData == true ? structured : nil,
            readableText: readable,
            imageURL: imageURL
        )
    }

    private static func scoreOf(_ recipe: StructuredWebRecipe) -> Int {
        recipe.ingredientLines.count * 2 + recipe.instructionSections.reduce(0) { $0 + $1.steps.count }
    }

    // MARK: JSON-LD

    static func structuredRecipes(in html: String, baseURL: URL) -> [StructuredWebRecipe] {
        let scripts = captures(
            "<script[^>]*type\\s*=\\s*[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>",
            in: html
        )
        var recipes: [StructuredWebRecipe] = []
        for script in scripts {
            let cleaned = script
                .replacingOccurrences(of: "<!--", with: "")
                .replacingOccurrences(of: "-->", with: "")
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = cleaned.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                continue
            }
            for object in recipeObjects(in: json) {
                recipes.append(structuredRecipe(from: object, baseURL: baseURL))
            }
        }
        return recipes
    }

    /// Walks the document for every object whose @type is Recipe, whether it
    /// sits at the top level, in @graph, or nested in an article.
    private static func recipeObjects(in json: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 8 else { return [] }
        if let array = json as? [Any] {
            return array.flatMap { recipeObjects(in: $0, depth: depth + 1) }
        }
        guard let dictionary = json as? [String: Any] else { return [] }
        if isRecipeType(dictionary["@type"]) {
            return [dictionary]
        }
        return dictionary.values.flatMap { recipeObjects(in: $0, depth: depth + 1) }
    }

    private static func isRecipeType(_ value: Any?) -> Bool {
        if let string = value as? String {
            return string.lowercased().hasSuffix("recipe")
        }
        if let strings = value as? [String] {
            return strings.contains { $0.lowercased().hasSuffix("recipe") }
        }
        return false
    }

    private static func structuredRecipe(from object: [String: Any], baseURL: URL) -> StructuredWebRecipe {
        var recipe = StructuredWebRecipe()
        recipe.name = plainText(object["name"]) ?? ""
        recipe.summary = plainText(object["description"]) ?? ""
        recipe.language = (plainText(object["inLanguage"]) ?? "")
            .split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)?.lowercased() ?? ""
        recipe.imageURL = imageURL(from: object["image"], baseURL: baseURL)
        recipe.ingredientLines = stringList(object["recipeIngredient"] ?? object["ingredients"])
        recipe.instructionSections = instructionSections(from: object["recipeInstructions"])
        recipe.prepMinutes = isoMinutes(object["prepTime"])
        recipe.cookMinutes = isoMinutes(object["cookTime"])
        recipe.totalMinutes = isoMinutes(object["totalTime"])
        recipe.keywords = keywords(from: object["keywords"])
        recipe.yield = stringList(object["recipeYield"]).first ?? ""
        return recipe
    }

    private static func imageURL(from value: Any?, baseURL: URL) -> URL? {
        guard let value else { return nil }
        if let string = value as? String {
            return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: baseURL)?.absoluteURL
        }
        if let array = value as? [Any] {
            return array.lazy.compactMap { imageURL(from: $0, baseURL: baseURL) }.first
        }
        if let dictionary = value as? [String: Any] {
            return imageURL(from: dictionary["url"] ?? dictionary["contentUrl"], baseURL: baseURL)
        }
        return nil
    }

    private static func stringList(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let string = value as? String {
            return string
                .components(separatedBy: .newlines)
                .compactMap { plainText($0) }
        }
        if let number = value as? NSNumber {
            return [number.stringValue]
        }
        if let array = value as? [Any] {
            return array.flatMap { stringList($0) }
        }
        if let dictionary = value as? [String: Any] {
            return stringList(dictionary["text"] ?? dictionary["name"])
        }
        return []
    }

    private static func instructionSections(from value: Any?) -> [StructuredInstructionSection] {
        guard let value else { return [] }
        if let string = value as? String {
            let steps = splitInstructionText(string)
            return steps.isEmpty ? [] : [StructuredInstructionSection(steps: steps)]
        }
        if let dictionary = value as? [String: Any] {
            return instructionSections(from: [dictionary])
        }
        guard let array = value as? [Any] else { return [] }

        var sections: [StructuredInstructionSection] = []
        var loose = StructuredInstructionSection()
        for element in array {
            if let string = element as? String {
                loose.steps.append(contentsOf: splitInstructionText(string))
            } else if let dictionary = element as? [String: Any] {
                let type = (dictionary["@type"] as? String ?? "").lowercased()
                if type.hasSuffix("section") || type == "itemlist" || dictionary["itemListElement"] != nil {
                    if !loose.steps.isEmpty { sections.append(loose); loose = StructuredInstructionSection() }
                    var section = StructuredInstructionSection(name: plainText(dictionary["name"]) ?? "")
                    section.steps = instructionSections(from: dictionary["itemListElement"]).flatMap(\.steps)
                    if !section.steps.isEmpty { sections.append(section) }
                } else if let text = plainText(dictionary["text"]) ?? plainText(dictionary["name"]) {
                    loose.steps.append(contentsOf: splitInstructionText(text))
                }
            }
        }
        if !loose.steps.isEmpty { sections.append(loose) }
        return sections
    }

    /// A single instruction string often holds every step, separated by line
    /// breaks or numbered; a short one is one step.
    private static func splitInstructionText(_ text: String) -> [String] {
        let plain = plainText(text) ?? ""
        guard !plain.isEmpty else { return [] }
        let parts = plain
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.map(removingStepNumber)
    }

    private static func removingStepNumber(_ step: String) -> String {
        step.replacingOccurrences(of: "^\\s*(?:Schritt|Step|Étape)?\\s*\\d{1,2}\\s*[.):]\\s*", with: "", options: [.regularExpression, .caseInsensitive])
    }

    private static func keywords(from value: Any?) -> [String] {
        stringList(value)
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Minutes in an ISO 8601 duration such as PT1H30M or P0DT12H.
    static func isoMinutes(_ value: Any?) -> Int {
        guard let string = value as? String else { return 0 }
        let upper = string.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard upper.hasPrefix("P") else { return 0 }
        var minutes = 0.0
        if let days = firstNumber("(\\d+(?:[.,]\\d+)?)D", in: upper) { minutes += days * 24 * 60 }
        if let timePart = upper.split(separator: "T").dropFirst().first.map(String.init) {
            if let hours = firstNumber("(\\d+(?:[.,]\\d+)?)H", in: timePart) { minutes += hours * 60 }
            if let mins = firstNumber("(\\d+(?:[.,]\\d+)?)M", in: timePart) { minutes += mins }
        }
        return Int(minutes.rounded())
    }

    private static func firstNumber(_ pattern: String, in text: String) -> Double? {
        captures(pattern, in: text).first.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    /// A string value freed of markup and entities; nil when nothing is left.
    private static func plainText(_ value: Any?) -> String? {
        guard let string = value as? String else {
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
        let text = decodingEntities(stripTags(string))
            .replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: Page text

    /// The visible text of the page's main content, one block per line:
    /// what a person sees once navigation, scripts and footers are gone.
    static func readableText(from html: String) -> String {
        var text = html
        for element in ["script", "style", "noscript", "svg", "template", "iframe"] {
            text = removingElements(element, from: text)
        }
        // (?s) lets the dot cross line breaks; replacingOccurrences does not
        // set that option on its own, so multi-line blocks would survive.
        text = text.replacingOccurrences(of: "(?s)<!--.*?-->", with: "", options: [.regularExpression, .caseInsensitive])

        text = mainContent(of: text)
        for element in ["nav", "header", "footer", "aside", "form", "figure", "button", "select"] {
            text = removingElements(element, from: text)
        }

        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li\\b[^>]*>", with: "\n- ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</?(?:p|div|li|ul|ol|h[1-6]|tr|table|section|article|main|blockquote|dd|dt|dl|pre|hr)\\b[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</t[dh]>", with: " \t", options: [.regularExpression, .caseInsensitive])
        text = stripTags(text)
        text = decodingEntities(text)

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        var previous = ""
        for line in lines where !line.isEmpty && line != previous && line != "-" {
            result.append(line)
            previous = line
        }
        return String(result.joined(separator: "\n").prefix(maximumReadableCharacters))
    }

    /// The article or main element when the page has one. Comments on blogs
    /// are articles too, so the longest one wins; a short one is only a
    /// teaser, and then the whole body is the safer source.
    private static func mainContent(of html: String) -> String {
        for element in ["article", "main"] {
            let bodies = captures("<\(element)\\b[^>]*>(.*?)</\(element)>", in: html)
            if let longest = bodies.max(by: { $0.count < $1.count }), longest.count >= 2_000 {
                return longest
            }
        }
        if let body = captures("<body\\b[^>]*>(.*)</body>", in: html).first {
            return body
        }
        return html
    }

    private static func removingElements(_ element: String, from html: String) -> String {
        html.replacingOccurrences(
            of: "(?s)<\(element)\\b[^>]*>.*?</\(element)\\s*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func metaContent(property: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            "<meta[^>]+(?:property|name)\\s*=\\s*[\"']\(escaped)[\"'][^>]+content\\s*=\\s*[\"']([^\"']+)[\"']",
            "<meta[^>]+content\\s*=\\s*[\"']([^\"']+)[\"'][^>]+(?:property|name)\\s*=\\s*[\"']\(escaped)[\"']"
        ]
        for pattern in patterns {
            if let value = captures(pattern, in: html).first {
                return plainText(value)
            }
        }
        return nil
    }

    private static func htmlTitle(in html: String) -> String? {
        captures("<title[^>]*>(.*?)</title>", in: html).first.flatMap { plainText($0) }
    }

    private static func htmlLanguage(in html: String) -> String? {
        captures("<html[^>]+lang\\s*=\\s*[\"']([A-Za-z]{2})", in: html).first?.lowercased()
    }

    // MARK: Entities and encoding

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "agrave": "à", "acirc": "â", "ccedil": "ç",
        "ocirc": "ô", "ucirc": "û", "ugrave": "ù", "icirc": "î", "iuml": "ï", "euml": "ë",
        "Eacute": "É", "Egrave": "È", "Agrave": "À", "Ccedil": "Ç",
        "frac12": "½", "frac14": "¼", "frac34": "¾", "deg": "°", "times": "×", "middot": "·",
        "bull": "•", "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "bdquo": "„", "laquo": "«", "raquo": "»", "euro": "€",
        "copy": "©", "reg": "®", "trade": "™", "shy": "", "thinsp": " ", "ensp": " ", "emsp": " "
    ]

    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        guard let regex = try? NSRegularExpression(pattern: "&(#x[0-9A-Fa-f]{1,6}|#\\d{1,7}|[A-Za-z][A-Za-z0-9]{1,10});") else {
            return text
        }
        let nsText = text as NSString
        var result = ""
        var location = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: location, length: match.range.location - location))
            let entity = nsText.substring(with: match.range(at: 1))
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                if let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                    result.unicodeScalars.append(scalar)
                } else {
                    result += nsText.substring(with: match.range)
                }
            } else if entity.hasPrefix("#") {
                if let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                    result.unicodeScalars.append(scalar)
                } else {
                    result += nsText.substring(with: match.range)
                }
            } else if let replacement = namedEntities[entity] {
                result += replacement
            } else {
                result += nsText.substring(with: match.range)
            }
            location = match.range.location + match.range.length
        }
        result += nsText.substring(from: location)
        return result
    }

    private static func decodeHTML(_ data: Data, declaredEncodingName: String?) -> String {
        var candidates: [String.Encoding] = []
        if let declaredEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(declaredEncodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                candidates.append(String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding)))
            }
        }
        if let head = String(data: data.prefix(4_096), encoding: .ascii) ?? String(data: data.prefix(4_096), encoding: .isoLatin1),
           let charset = captures("charset\\s*=\\s*[\"']?([A-Za-z0-9_-]+)", in: head).first {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                candidates.append(String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding)))
            }
        }
        candidates.append(contentsOf: [.utf8, .isoLatin1])
        for encoding in candidates {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
            return nsText.substring(with: match.range(at: 1))
        }
    }
}

// MARK: - Rule-based recipe from structured data

extension StructuredWebRecipe {

    /// A recipe built from the structured data alone, for when neither AI
    /// stage is available. Ingredient lines are split into amount, unit and
    /// name; headings among them open a new component.
    @MainActor
    func makeRecipe() -> RecipeFB {
        let recipe = RecipeFB()
        recipe.name = name
        recipe.summary = summary
        recipe.sourceLanguage = language
        recipe.prepTime = totalMinutes > 0 ? totalMinutes : prepMinutes + cookMinutes
        recipe.tags = Array(keywords.prefix(8))

        var components: [ComponentFB] = []
        var current: ComponentFB?
        for line in ingredientLines {
            if let heading = Self.componentHeading(in: line) {
                if let current, !current.ingredients.isEmpty { components.append(current) }
                let component = ComponentFB()
                component.id = UUID().uuidString
                component.name = heading
                current = component
                continue
            }
            let parsed = Self.parseIngredientLine(line)
            guard !parsed.name.isEmpty else { continue }
            if current == nil {
                let component = ComponentFB()
                component.id = UUID().uuidString
                component.name = String(localized: "Hauptteig", bundle: AppSettings.localizationBundle)
                current = component
            }
            let ingredient = IngredientFB()
            ingredient.id = UUID().uuidString
            ingredient.number = (current?.ingredients.count ?? 0) + 1
            ingredient.name = parsed.name
            ingredient.weight = parsed.amount
            ingredient.normWeight = parsed.amount
            ingredient.unit = parsed.unit
            current?.ingredients.append(ingredient)
        }
        if let current, !current.ingredients.isEmpty { components.append(current) }
        for (index, component) in components.enumerated() { component.number = index + 1 }
        recipe.components = components

        var instructions: [InstructionFB] = []
        let namedSections = instructionSections.filter { !$0.name.isEmpty }.count
        let isMultiComponent = components.count > 1 || namedSections > 1
        for section in instructionSections {
            for step in section.steps {
                let instruction = InstructionFB()
                instruction.id = UUID().uuidString
                instruction.step = Double(instructions.count + 1)
                instruction.instruction = RecipeImportStepText.text(
                    step, naming: section.name, inMultiComponentRecipe: isMultiComponent
                )
                instruction.duration = Self.explicitMinutes(in: step)
                if instruction.duration == 0, Self.describesOvenPreheating(step) {
                    instruction.duration = GlobalVariables.preheatTime
                }
                instruction.bakeFlag = Self.describesBaking(step)
                instruction.componentName = section.name.isEmpty ? nil : section.name
                instructions.append(instruction)
            }
        }
        recipe.instructions = instructions
        recipe.totalWeight = recipe.components.flatMap(\.ingredients).reduce(0) { $0 + $1.weight }
        return recipe
    }

    /// Lead-ins stripped from a heading, longest first so "für den" wins over "für".
    private static let headingPrefixes: [String] = [
        "für den ", "für die ", "für das ", "für ",
        "for the ", "for ",
        "pour le ", "pour la ", "pour les ", "pour l'", "pour "
    ]

    /// A line without an amount that reads like a heading: "Für den Vorteig:".
    static func componentHeading(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40,
              trimmed.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }
        let lower = trimmed.lowercased()
        let looksLikeHeading = trimmed.hasSuffix(":")
            || lower.hasPrefix("für ") || lower.hasPrefix("for the ") || lower.hasPrefix("pour ")
        guard looksLikeHeading else { return nil }
        var heading = trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : trimmed
        for prefix in headingPrefixes {
            if heading.lowercased().hasPrefix(prefix) {
                heading = String(heading.dropFirst(prefix.count))
                break
            }
        }
        heading = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heading.isEmpty else { return nil }
        return heading.prefix(1).uppercased() + heading.dropFirst()
    }

    private static let unitPattern = "(?:g|gr|gramm|grams?|kg|mg|ml|cl|dl|l|liter|litre|tl|el|msp|pr\\.?|prise|prisen|stk\\.?|stück|st\\.?|pck\\.?|päckchen|pkg\\.?|packung|bund|tasse|tassen|becher|tropfen|scheiben?|blatt|blätter|würfel|zehen?|cups?|tbsps?|tsps?|tablespoons?|teaspoons?|oz|ounces?|lbs?|pounds?|pinch|cloves?|pieces?|slices?|sticks?|c\\.? à s\\.?|c\\.? à c\\.?|cuillères? à soupe|cuillères? à café|cs|cc|pincée|sachets?|gousses?|tranches?|verres?)"

    /// Two capture groups: the amount and, for a range, its upper end.
    private static let amountPattern = "(\\d+(?:[.,]\\d+)?(?:\\s*(?:\\d+/\\d+|[½¼¾⅓⅔⅛]))?|\\d+/\\d+|[½¼¾⅓⅔⅛])(?:\\s*(?:-|–|bis|to|à)\\s*(\\d+(?:[.,]\\d+)?|[½¼¾⅓⅔⅛]))?"

    /// "500 g Weizenmehl 550" or "Weizenmehl 550 g" into its three parts;
    /// a line without a number keeps its text as the name.
    static func parseIngredientLine(_ line: String) -> (amount: Double, unit: String, name: String) {
        var text = line
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "^\\s*[-•*▢☐]\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (0, "", "") }

        // Groups: 1 amount, 2 upper end of a range, 3 unit, 4 name.
        let leading = "^" + amountPattern + "\\s*(" + unitPattern + ")?\\b\\.?\\s+(?:of |de |d')?(.+)$"
        if let match = firstMatch(leading, in: text), match.count == 5 {
            let amount = numericAmount(match[1], upper: match[2])
            return preferringMetricAmount(amount, canonicalUnit(match[3]), cleanName(match[4]))
        }
        // Groups: 1 name, 2 amount, 3 upper end of a range, 4 unit.
        let trailing = "^(.+?)[\\s:,]+" + amountPattern + "\\s*(" + unitPattern + ")?\\.?\\s*$"
        if let match = firstMatch(trailing, in: text), match.count == 5 {
            let amount = numericAmount(match[2], upper: match[3])
            return (amount, canonicalUnit(match[4]), cleanName(match[1]))
        }
        text = cleanName(text)
        return (0, "", text)
    }

    /// "1/2 cup (113g) water" is a baking recipe's way of printing grams;
    /// the metric figure in brackets is the one the scale needs.
    private static func preferringMetricAmount(_ amount: Double, _ unit: String, _ name: String) -> (amount: Double, unit: String, name: String) {
        let metric = "^\\(\\s*(?:(?:ca\\.|approx\\.|about|environ)\\s*)?(\\d+(?:[.,]\\d+)?)\\s*(g|ml)\\s*\\)\\s*(.+)$"
        guard let match = firstMatch(metric, in: name), match.count == 4,
              let metricAmount = Double(match[1].replacingOccurrences(of: ",", with: ".")) else {
            return (amount, unit, name)
        }
        return (metricAmount, match[2], cleanName(match[3]))
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : nsText.substring(with: range)
        }
    }

    private static func numericAmount(_ lower: String, upper: String) -> Double {
        let low = numericValue(lower)
        guard !upper.isEmpty else { return low }
        let high = numericValue(upper)
        return high > low ? (low + high) / 2 : low
    }

    /// "1 ½", "1½", "1 1/2", "1,5" and "0.5" all become a number; the parts
    /// of a mixed number are added up.
    private static func numericValue(_ text: String) -> Double {
        let fractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
        var total = 0.0
        var digits = ""
        func flush() {
            defer { digits = "" }
            guard !digits.isEmpty else { return }
            if digits.contains("/") {
                let halves = digits.split(separator: "/").compactMap { Double($0) }
                if halves.count == 2, halves[1] != 0 { total += halves[0] / halves[1] }
            } else if let value = Double(digits.replacingOccurrences(of: ",", with: ".")) {
                total += value
            }
        }
        for character in text {
            if let fraction = fractions[character] {
                flush()
                total += fraction
            } else if character == " " {
                flush()
            } else {
                digits.append(character)
            }
        }
        flush()
        return (total * 100).rounded() / 100
    }

    /// German abbreviations are written the way the app's unit list spells
    /// them; every other unit stays as printed, like the image import does.
    private static func canonicalUnit(_ unit: String) -> String {
        let trimmed = unit.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        switch lower {
        case "gr", "gramm", "gram", "grams": return "g"
        case "liter", "litre": return "l"
        case "tl": return "TL"
        case "el": return "EL"
        case "stk", "stück", "st": return "Stück"
        case "pr", "prise", "prisen": return "Prise"
        case "pck", "päckchen", "pkg", "packung": return "Päckchen"
        case "msp": return "Msp."
        default: return trimmed
        }
    }

    private static func cleanName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–"))
    }

    /// The longest explicitly stated duration in a step, in minutes. Ranges
    /// are averaged, hours converted; nothing is guessed.
    static func explicitMinutes(in text: String) -> Int {
        let pattern = "(\\d+(?:[.,]\\d+)?)(?:\\s*(?:-|–|bis|to|à|oder|or|ou)\\s*(\\d+(?:[.,]\\d+)?))?\\s*(min(?:ute[ns]?|s)?\\b\\.?|std\\.?|stunden?|h\\b|hours?|heures?|sek(?:unden)?|seconds?|sec)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        let nsText = text as NSString
        var longest = 0.0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let lower = Double(nsText.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")) ?? 0
            let upperRange = match.range(at: 2)
            let upper = upperRange.location == NSNotFound ? lower : (Double(nsText.substring(with: upperRange).replacingOccurrences(of: ",", with: ".")) ?? lower)
            let unit = nsText.substring(with: match.range(at: 3)).lowercased()
            var minutes = (lower + upper) / 2
            if unit.hasPrefix("st") || unit.hasPrefix("h") { minutes *= 60 }
            if unit.hasPrefix("se") { minutes /= 60 }
            longest = max(longest, minutes)
        }
        return Int(longest.rounded())
    }

    static func describesBaking(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["backen", "bake", "baking", "cuire", "enfourner", "in den ofen", "into the oven", "au four"]
            .contains { lower.contains($0) }
    }

    static func describesOvenPreheating(_ text: String) -> Bool {
        let normalized = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        let ovenTerms = ["ofen", "backofen", "oven", "four", "forno"]
        let preheatTerms = ["vorheiz", "aufheiz", "preheat", "prechauff"]
        return ovenTerms.contains(where: normalized.contains) && preheatTerms.contains(where: normalized.contains)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
