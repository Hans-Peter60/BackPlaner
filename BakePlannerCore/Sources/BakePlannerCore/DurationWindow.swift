//
//  DurationWindow.swift
//  BakePlannerCore
//
//  A step that may take between so and so long: "12–18 Stunden im
//  Kühlschrank", "30 bis 60 Minuten gehen lassen". The recipe keeps the
//  window with the step (`RecipeExportInstruction.minDuration` and
//  `.maxDuration`); where it has none, the step's wording may give one.
//  The plan advisor stretches or shortens such steps within their windows
//  to fit a plan into the day or the ovens before it moves the whole plan
//  (`BakePlanAdvisor.windowSuggestion`).
//

import Foundation

public enum DurationWindow {

    /// The window from its bounds, when both are there and it has a width.
    public static func range(minimum: Int?, maximum: Int?) -> ClosedRange<Int>? {
        guard let minimum, let maximum, minimum >= 0, maximum > minimum else { return nil }
        return minimum...maximum
    }

    /// The window a step's wording gives, in minutes: "12–18 Stunden",
    /// "30 bis 60 Minuten", "1 to 1.5 hours", "1 à 2 heures". Nil without
    /// one, and for the bake and the preheating, whose time is the oven's.
    public static func parse(_ instruction: String) -> ClosedRange<Int>? {
        guard !BakePlanValidator.isBakingStartInstruction(instruction),
              !BakePlanValidator.isPreheatInstruction(instruction) else { return nil }
        let text = instruction.lowercased()
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(?:-|–|—|bis|to|à|a|ou|or|oder)\s*(\d+(?:[.,]\d+)?)\s*(min(?:ute[ns]?|s)?\b\.?|std\.?|stunden?|h\b|hours?|heures?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let lowerRange = Range(match.range(at: 1), in: text),
                  let upperRange = Range(match.range(at: 2), in: text),
                  let unitRange = Range(match.range(at: 3), in: text),
                  let lower = Double(text[lowerRange].replacingOccurrences(of: ",", with: ".")),
                  let upper = Double(text[upperRange].replacingOccurrences(of: ",", with: ".")),
                  lower < upper else { continue }
            let unit = text[unitRange]
            let factor: Double = unit.hasPrefix("st") || unit.hasPrefix("h") ? 60 : 1
            let minimum = Int((lower * factor).rounded())
            let maximum = Int((upper * factor).rounded())
            if let window = range(minimum: minimum, maximum: maximum) { return window }
        }
        return nil
    }

    /// The window a plan step may use: the stored one when the recipe has
    /// it, else the one the wording gives, if the step's duration lies
    /// within it — a step the baker shortened below the text's range is
    /// no longer the text's step.
    public static func effective(stored: ClosedRange<Int>?, instruction: String, duration: Int) -> ClosedRange<Int>? {
        if let stored { return stored }
        guard duration > 0, let parsed = parse(instruction), parsed.contains(duration) else { return nil }
        return parsed
    }

    /// "12h 00m – 18h 00m", "30m – 60m", as the tables show durations.
    public static func text(_ window: ClosedRange<Int>) -> String {
        "\(Rational.displayHoursMinutes(window.lowerBound)) – \(Rational.displayHoursMinutes(window.upperBound))"
    }
}

extension Rational.ComponentDependency {
    /// The dependencies of a recipe's components as the backup format has
    /// them, the rule of the FB and Core Data forms: an ingredient without
    /// a weight that names another component uses that component up.
    public static func from(_ components: [RecipeExportComponent]) -> [Rational.ComponentDependency] {
        let names = components.map(\.name)
        return components.map { component in
            Rational.ComponentDependency(
                name: component.name,
                requires: requirements(of: component.ingredients.filter { $0.weight == 0 }.map(\.name),
                                       componentNames: names,
                                       excluding: component.name)
            )
        }
    }
}
