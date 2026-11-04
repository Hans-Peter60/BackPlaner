//
//  RecipeTextImport.swift
//  BakePlannerCore
//
//  The third way into the app: recipe text the person copied and pasted,
//  for pages that only deliver their recipe through JavaScript and so give
//  the web import nothing. The text goes through the same stages as a web
//  page's text — cloud AI, Apple Intelligence on the iPhone — and this
//  file is the stage that needs no model: it reads the text by the
//  headings a recipe is usually printed with ("Zutaten", "Zubereitung",
//  "Für den Sauerteig:") into a StructuredWebRecipe, which already knows
//  how to become a recipe.
//

import Foundation

/// Why pasted text could not be imported.
public enum RecipeTextImportError: LocalizedError, Equatable {
    /// Fewer characters than any recipe has.
    case tooShort
    /// The text is nothing but a web address; the web import is the way.
    case looksLikeAddress(URL)
    /// No ingredient lines and steps could be made out.
    case noRecipeFound

    public var errorDescription: String? {
        switch self {
        case .tooShort:
            return String(localized: "Der eingefügte Text ist zu kurz für ein Rezept.", bundle: AppSettings.localizationBundle)
        case .looksLikeAddress:
            return String(localized: "Das ist nur eine Internetadresse. Nutze dafür den Import von einer Internetseite, oder füge den Text der Seite ein.", bundle: AppSettings.localizationBundle)
        case .noRecipeFound:
            return String(localized: "Im eingefügten Text wurden keine Zutaten und Arbeitsschritte gefunden. Überschriften wie „Zutaten“ und „Zubereitung“ helfen der Erkennung.", bundle: AppSettings.localizationBundle)
        }
    }
}

/// Recipe text as the person pasted it, cleaned up and read by rules.
public enum PastedRecipeText {

    /// Below this a text is not a recipe, whatever it says.
    public static let minimumCharacters = 40
    /// The analysis stages read no more than this, like a web page's text.
    public static let maximumCharacters = RecipeWebPageLoader.maximumAnalysisCharacters

    // MARK: - Cleaning

    /// The text with one kind of line break, no non-breaking spaces, no
    /// trailing blanks, runs of empty lines reduced to one, and cut to
    /// `maximumCharacters`.
    public static func normalized(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        var lines: [String] = []
        var previousWasEmpty = true
        for rawLine in unified.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if !previousWasEmpty { lines.append("") }
                previousWasEmpty = true
            } else {
                lines.append(line)
                previousWasEmpty = false
            }
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return String(lines.joined(separator: "\n").prefix(maximumCharacters))
    }

    /// The cleaned text, or the reason it cannot be analysed: too short, or
    /// only an address.
    public static func validated(_ text: String) throws -> String {
        let cleaned = normalized(text)
        if let address = addressOnly(in: cleaned) {
            throw RecipeTextImportError.looksLikeAddress(address)
        }
        guard cleaned.count >= minimumCharacters else {
            throw RecipeTextImportError.tooShort
        }
        return cleaned
    }

    /// The address when the text is one and nothing else.
    public static func addressOnly(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\n") else { return nil }
        return RecipeWebPageLoader.normalizedURL(from: trimmed)
    }

    // MARK: - Reading by rules

    /// The language of the headings the text was recognised by: "de", "en"
    /// or "fr", empty when no heading gave it away.
    private enum Section {
        case introduction
        case ingredients
        case instructions
        case other
    }

    private struct Heading {
        let section: Section
        let language: String
    }

    /// The recipe read from the text by its headings, or nil when the text
    /// yields no ingredients or no steps. Components open with a heading
    /// line ("Sauerteig", "Für den Vorteig:"), steps are the paragraphs of
    /// the method; without any section heading, ingredient lines are told
    /// apart from steps by their shape.
    public static func structuredRecipe(from text: String) -> StructuredWebRecipe? {
        let lines = normalized(text).components(separatedBy: "\n")
        guard !lines.isEmpty else { return nil }

        var recipe = StructuredWebRecipe()
        var introduction: [String] = []
        var ingredientLines: [String] = []
        var sections: [StructuredInstructionSection] = [StructuredInstructionSection()]
        var section = Section.introduction
        var sawSectionHeading = false
        var pendingStep: String?

        func closeStep() {
            if let step = pendingStep, !step.isEmpty {
                sections[sections.count - 1].steps.append(step)
            }
            pendingStep = nil
        }

        for line in lines {
            if line.isEmpty {
                if section == .instructions { closeStep() }
                continue
            }
            if let heading = sectionHeading(in: line) {
                closeStep()
                sawSectionHeading = true
                section = heading.section
                if recipe.language.isEmpty { recipe.language = heading.language }
                continue
            }
            switch section {
            case .introduction:
                introduction.append(line)
            case .ingredients:
                if let component = componentHeading(in: line) {
                    ingredientLines.append(component + ":")
                } else if isIngredientLine(line) {
                    ingredientLines.append(line)
                } else if sawSectionHeading, looksLikeStep(line), !ingredientLines.isEmpty {
                    // The method began without a heading of its own.
                    section = .instructions
                    pendingStep = stepText(line)
                }
            case .instructions:
                if let component = componentHeading(in: line) {
                    closeStep()
                    if sections.last?.steps.isEmpty == true, sections.last?.name.isEmpty == true {
                        sections[sections.count - 1].name = component
                    } else {
                        sections.append(StructuredInstructionSection(name: component))
                    }
                } else if let pending = pendingStep, continuesSentence(pending, with: line) {
                    pendingStep = pending + " " + stepText(line)
                } else {
                    closeStep()
                    pendingStep = stepText(line)
                }
            case .other:
                continue
            }
        }
        closeStep()

        if !sawSectionHeading {
            // No headings at all: sort every line by its shape instead.
            return recipeWithoutHeadings(lines)
        }

        recipe.name = title(in: introduction) ?? ""
        recipe.summary = summary(in: introduction, excluding: recipe.name)
        recipe.ingredientLines = ingredientLines
        recipe.instructionSections = sections.filter { !$0.steps.isEmpty }
        return recipe.hasIngredientsAndSteps ? recipe : nil
    }

    /// A text without "Zutaten"/"Zubereitung": ingredient lines carry an
    /// amount and are short, steps are sentences, the first line is the
    /// name. Component headings still open components and sections.
    private static func recipeWithoutHeadings(_ lines: [String]) -> StructuredWebRecipe? {
        var recipe = StructuredWebRecipe()
        var ingredientLines: [String] = []
        var sections: [StructuredInstructionSection] = [StructuredInstructionSection()]
        var currentComponent: String?
        var introduction: [String] = []
        var pendingStep: String?

        func closeStep() {
            if let step = pendingStep, !step.isEmpty {
                sections[sections.count - 1].steps.append(step)
            }
            pendingStep = nil
        }

        for line in lines {
            if line.isEmpty { closeStep(); continue }
            if let component = componentHeading(in: line) {
                closeStep()
                currentComponent = component
                continue
            }
            if isIngredientLine(line), StructuredWebRecipe.parseIngredientLine(line).amount > 0 {
                closeStep()
                if let component = currentComponent {
                    ingredientLines.append(component + ":")
                    currentComponent = nil
                }
                ingredientLines.append(line)
            } else if looksLikeStep(line) {
                if let component = currentComponent {
                    closeStep()
                    if sections.last?.steps.isEmpty == true, sections.last?.name.isEmpty == true {
                        sections[sections.count - 1].name = component
                    } else {
                        sections.append(StructuredInstructionSection(name: component))
                    }
                    currentComponent = nil
                }
                if let pending = pendingStep, continuesSentence(pending, with: line) {
                    pendingStep = pending + " " + stepText(line)
                } else {
                    closeStep()
                    pendingStep = stepText(line)
                }
            } else if ingredientLines.isEmpty, sections.allSatisfy({ $0.steps.isEmpty }), pendingStep == nil {
                introduction.append(line)
            }
        }
        closeStep()

        recipe.name = title(in: introduction) ?? ""
        recipe.summary = summary(in: introduction, excluding: recipe.name)
        recipe.ingredientLines = ingredientLines
        recipe.instructionSections = sections.filter { !$0.steps.isEmpty }
        return recipe.hasIngredientsAndSteps ? recipe : nil
    }

    // MARK: - Lines

    private static let ingredientHeadings: [(String, String)] = [
        ("zutaten", "de"), ("zutatenliste", "de"),
        ("ingredients", "en"), ("ingredient list", "en"),
        ("ingrédients", "fr"), ("ingredients", "fr"),
    ]

    private static let instructionHeadings: [(String, String)] = [
        ("zubereitung", "de"), ("anleitung", "de"), ("herstellung", "de"), ("arbeitsschritte", "de"),
        ("zubereitungsschritte", "de"), ("so geht's", "de"), ("so geht’s", "de"), ("so wird's gemacht", "de"),
        ("so wird’s gemacht", "de"), ("ablauf", "de"),
        ("method", "en"), ("instructions", "en"), ("directions", "en"), ("preparation", "en"), ("steps", "en"),
        ("how to make it", "en"),
        ("préparation", "fr"), ("preparation", "fr"), ("étapes", "fr"), ("etapes", "fr"), ("réalisation", "fr"),
        ("marche à suivre", "fr"), ("instructions", "fr"),
    ]

    /// What follows the method on a page and is no step: tips, nutrition,
    /// comments, the next recipe.
    private static let otherHeadings = [
        "tipp", "tipps", "hinweis", "hinweise", "anmerkungen", "nährwerte", "kommentare", "das könnte dich auch interessieren",
        "notes", "note", "tips", "nutrition", "nutrition facts", "comments", "you might also like",
        "conseils", "astuces", "remarques", "valeurs nutritionnelles", "commentaires",
    ]

    /// "Zutaten", "Zutaten für 2 Brote:", "Method" — the line that opens a
    /// section, with the language it is written in.
    private static func sectionHeading(in line: String) -> Heading? {
        var text = line.lowercased()
        text = text.replacingOccurrences(of: "^[#*\\-–•\\s]+", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ": *_").union(.whitespaces))
        guard !text.isEmpty, text.count <= 40 else { return nil }
        for (heading, language) in ingredientHeadings where text == heading || text.hasPrefix(heading + " ") {
            // "Zutaten für 2 Brote" is a heading; "Zutaten in eine Schüssel geben" is a step.
            if text == heading || text.hasPrefix(heading + " für ") || text.hasPrefix(heading + " for ")
                || text.hasPrefix(heading + " pour ") || text.hasPrefix(heading + " (") {
                return Heading(section: .ingredients, language: language)
            }
        }
        for (heading, language) in instructionHeadings where text == heading || text.hasPrefix(heading + " (") {
            return Heading(section: .instructions, language: language)
        }
        for heading in otherHeadings where text == heading {
            return Heading(section: .other, language: "")
        }
        return nil
    }

    /// Words a component heading is made of, on their own or after
    /// "für den": "Sauerteig", "Poolish", "Hauptteig (TA 170)".
    private static let componentWords = [
        "sauerteig", "vorteig", "hauptteig", "poolish", "biga", "brühstück", "quellstück", "kochstück",
        "autolyse", "autolyseteig", "mehlkochstück", "aromastück", "anstellgut", "lievito madre", "madre",
        "levain", "levain-chef", "pâte fermentée", "pate fermentee", "pâte principale", "pâte finale",
        "starter", "preferment", "pre-ferment", "sponge", "soaker", "scald", "tangzhong", "main dough",
        "final dough", "dough", "teig", "füllung", "filling", "garniture", "glasur", "glaze", "streusel",
        "topping", "belag", "sirup", "syrup", "sirop", "fermentation", "formen", "backen",
    ]

    /// A short line without an amount that names a component.
    static func componentHeading(in line: String) -> String? {
        if let heading = StructuredWebRecipe.componentHeading(in: line) {
            return heading
        }
        let trimmed = line
            .replacingOccurrences(of: "^[#*\\-–•\\s]+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 40, !trimmed.hasSuffix(".") else { return nil }
        let withoutParenthesis = trimmed
            .replacingOccurrences(of: "\\s*\\([^)]*\\)\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // A heading is capitalised; "gesamter Sauerteig" in the main dough's
        // ingredients is a line about a component, not a component.
        guard withoutParenthesis.rangeOfCharacter(from: .decimalDigits) == nil,
              withoutParenthesis.split(separator: " ").count <= 3,
              withoutParenthesis.first?.isUppercase == true else { return nil }
        let lower = withoutParenthesis.lowercased()
        let wholeComponentLeadIns = ["gesamter ", "gesamten ", "gesamtes ", "ganzer ", "ganzen ", "ganzes ", "alle ", "all ", "the ", "whole ", "tout ", "toute ", "le ", "la "]
        guard !wholeComponentLeadIns.contains(where: lower.hasPrefix),
              componentWords.contains(where: { lower == $0 || lower.hasSuffix(" " + $0) || lower.hasSuffix($0) }) else {
            return nil
        }
        return withoutParenthesis.prefix(1).uppercased() + withoutParenthesis.dropFirst()
    }

    /// Whether a line reads like one ingredient: an amount up front or at
    /// the end, or a short bare name such as "Salz".
    static func isIngredientLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 90 else { return false }
        let parsed = StructuredWebRecipe.parseIngredientLine(trimmed)
        guard !parsed.name.isEmpty else { return false }
        if parsed.amount > 0 { return !looksLikeStep(trimmed) || !parsed.unit.isEmpty }
        // No number: a bare name, not a sentence.
        let words = trimmed.split(separator: " ").count
        return words <= 5 && !trimmed.hasSuffix(".") && !trimmed.hasSuffix(":")
    }

    /// Whether a line reads like a step: a sentence of several words.
    static func looksLikeStep(_ line: String) -> Bool {
        let words = line.split(separator: " ").count
        guard words >= 4 else { return false }
        if line.hasSuffix(".") || line.hasSuffix("!") { return true }
        // "500 g Mehl in eine Schüssel geben" ends without a period but
        // is long; "100 g Wasser (50 °C)" is not.
        return words >= 7 || line.range(of: "^\\s*(\\d+[.)]|schritt\\s+\\d+|step\\s+\\d+|étape\\s+\\d+)", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The step without its number: "1. ", "2) ", "Schritt 3:".
    static func stepText(_ line: String) -> String {
        line.replacingOccurrences(
            of: "^\\s*(?:(?:schritt|step|étape|etape)\\s+\\d+\\s*[:.)]?|\\d+\\s*[.)]|[-–•*])\\s*",
            with: "", options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespaces)
    }

    /// A line that is the rest of the previous sentence: the previous one
    /// did not end, this one starts in lower case.
    private static func continuesSentence(_ previous: String, with line: String) -> Bool {
        guard let last = previous.last, let first = line.first else { return false }
        return !".!?:".contains(last) && first.isLowercase
    }

    /// The first short line of the introduction that is no heading and no
    /// ingredient; the recipe's name on most pages.
    private static func title(in introduction: [String]) -> String? {
        introduction.first { line in
            line.count <= 80 && componentHeading(in: line) == nil
                && line.first?.isNumber != true
        }
    }

    /// The rest of the introduction as the summary, unless it is so long
    /// that it is the page rather than the recipe.
    private static func summary(in introduction: [String], excluding title: String) -> String {
        let rest = introduction.filter { $0 != title }.joined(separator: "\n")
        return rest.count <= 600 ? rest : ""
    }
}

private extension StructuredWebRecipe {
    var hasIngredientsAndSteps: Bool {
        ingredientLines.contains { !$0.hasSuffix(":") } && instructionSections.contains { !$0.steps.isEmpty }
    }
}
