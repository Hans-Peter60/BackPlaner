//
//  TimedFoldExpansion.swift
//  BackPlaner
//
//  Turns one instruction that describes repeated stretch-and-folds during a
//  rest or rise into one generated step per fold, each carrying the remaining
//  duration of the parent step from that point on. Recognises an explicit list
//  of offsets ("nach 30, 60 und 90 Minuten", "in den ersten 30 und 60
//  Minuten") and an interval with an optional repeat count ("alle 30 Minuten
//  falten, 4x"); without an explicit count, the interval repeats for as long
//  as the parent step's duration allows. Shared by every import parser
//  (GeneralRecipeParser, TwoColumnRecipeParser, RecipeWebPageLoader) and by
//  the forms that enter or edit a recipe by hand, so the recognised wording
//  doesn't depend on where the recipe came from.
//

import BakePlannerCore
import Foundation

enum TimedFoldExpansion {

    /// Expands every fold instruction in `instructions`. Returns whether
    /// anything changed.
    @discardableResult
    static func expand(_ instructions: inout [InstructionFB]) -> Bool {
        var handled = Set<ObjectIdentifier>()
        var changed = false
        // One fold line at a time: the generated steps mention "nach … Minuten"
        // themselves and must not be taken for another fold schedule, and a
        // recipe may fold during more than one rest.
        while let foldIndex = instructions.firstIndex(where: {
            !handled.contains(ObjectIdentifier($0)) && isFoldCandidate($0)
        }) {
            handled.insert(ObjectIdentifier(instructions[foldIndex]))
            if let generated = expand(&instructions, foldIndex: foldIndex) {
                generated.forEach { handled.insert(ObjectIdentifier($0)) }
                changed = true
            }
        }
        return changed
    }

    /// Expands the fold instruction at `foldIndex`; returns the generated
    /// steps, or nil when the line does not describe a fold schedule after
    /// all.
    private static func expand(_ instructions: inout [InstructionFB], foldIndex: Int) -> [InstructionFB]? {
        let foldInstruction = instructions[foldIndex]
        let foldText = normalized(foldInstruction.instruction)

        guard let parentIndex = parentStepIndex(for: foldText, foldIndex: foldIndex, in: instructions) else {
            return nil
        }

        let parent = instructions[parentIndex]
        // A duration the recipe already carries wins over the one read from
        // the text: "8–12 Stunden" reads as 12 hours, while the recipe may
        // say 10.
        let totalDuration = parent.duration > 0 ? parent.duration : parsedDuration(in: parent.instruction)
        guard totalDuration > 0 else { return nil }

        let wanted = foldOffsets(in: foldText, totalDuration: totalDuration)
        guard !wanted.isEmpty else { return nil }

        // Folds the rest already has, as sub-steps 3.1, 3.2 … from an earlier
        // expansion or typed by hand: a rest line that states its own folds
        // is run through here every time its step is saved, and used to
        // gain a second set of fold steps each time. Only offsets without a
        // step are added, numbered after the existing ones.
        let existing = instructions.filter {
            $0 !== parent && $0.step > parent.step && $0.step < parent.step + 1
        }
        let existingOffsets = Set(existing.compactMap(generatedFoldOffset))
        let offsets = wanted.filter { !existingOffsets.contains($0) }
        guard !offsets.isEmpty else { return nil }

        parent.duration = totalDuration

        let firstNumber = existing.count + 1
        let foldSteps = offsets.enumerated().map { index, offset -> InstructionFB in
            let step = InstructionFB()
            step.id = UUID().uuidString
            step.step = parent.step + 0.1 * Double(firstNumber + index)
            step.instruction = "Teig dehnen und falten (nach \(offset) Minuten)."
            step.duration = totalDuration - offset
            return step
        }

        if foldIndex == parentIndex {
            instructions.insert(contentsOf: foldSteps, at: parentIndex + 1 + existing.count)
        } else {
            let removedStep = foldInstruction.step
            instructions.remove(at: foldIndex)
            instructions.insert(contentsOf: foldSteps, at: parentIndex + 1)
            for instruction in instructions where instruction.step >= removedStep {
                instruction.step -= 1
            }
        }
        return foldSteps
    }

    // MARK: - Detection

    /// The offset of a fold step this expansion generated ("Teig dehnen und
    /// falten (nach 30 Minuten).") or of one worded the same way by hand;
    /// nil for any other step.
    private static func generatedFoldOffset(_ instruction: InstructionFB) -> Int? {
        let value = normalized(instruction.instruction)
        guard value.contains("dehnen und falten"),
              let offset = captures(#"nach\s+(\d+)\s*minuten"#, in: value)?.first else { return nil }
        return Int(offset)
    }

    private static func isFoldCandidate(_ instruction: InstructionFB) -> Bool {
        let value = normalized(instruction.instruction)
        guard value.contains("dehnen") || value.contains("denen") else { return false }
        guard value.contains("falten") else { return false }
        return value.contains("nach ") || value.contains("alle ") || value.contains("ersten ")
    }

    /// The words that make a step a rest or rise the folds happen during.
    private static let restWords = [
        "ruhen lassen", "reifen lassen", "gehen lassen", "stehen lassen", "lagern",
        "ruhen", "reifen", "gare", "fermentieren"
    ]

    private static func describesRest(_ text: String) -> Bool {
        restWords.contains { text.contains($0) }
    }

    /// The fold line itself names its own rest when it already states the
    /// duration ("... 12 Stunden ruhen lassen. Dabei nach 30 und 60 Minuten
    /// falten.", "8–12 Stunden bei 9 °C lagern und in den ersten 30 und 60
    /// Minuten falten"); otherwise the most recent preceding rest/rise step
    /// is the one the folds happen during.
    private static func parentStepIndex(
        for foldText: String, foldIndex: Int, in instructions: [InstructionFB]
    ) -> Int? {
        if foldText.contains("stunden") && describesRest(foldText) {
            return foldIndex
        }
        return instructions[..<foldIndex].lastIndex(where: {
            let value = normalized($0.instruction)
            return value.contains("stunden") && describesRest(value)
        })
    }

    /// The minute offsets at which a fold happens. Offsets beyond the parent
    /// step's duration are dropped — a fold cannot happen after the rest it
    /// belongs to is already over.
    private static func foldOffsets(in text: String, totalDuration: Int) -> [Int] {
        if let explicit = explicitOffsets(in: text) {
            let kept = explicit.filter { $0 <= totalDuration }
            return kept.count >= 2 ? kept : []
        }
        return intervalOffsets(in: text, totalDuration: totalDuration)
    }

    /// "nach 30, 60 und 90 minuten" or "in den ersten 30 und 60 minuten" →
    /// [30, 60, 90]. Only numbers and their connectors may stand between the
    /// lead-in and "minuten", so "bei 9 °C lagern und in den ersten …" does
    /// not sweep the temperature in. Requires at least two offsets to
    /// survive — a single "nach 30 minuten" reads more like a one-off timing
    /// note than a fold schedule, and a single repeated fold time is already
    /// covered by the interval pattern below.
    private static func explicitOffsets(in text: String) -> [Int]? {
        let pattern = #"(?:nach|in den ersten)\s+((?:\d+\s*(?:,|und|&|\+|sowie)?\s*)+)minuten"#
        guard let segment = captures(pattern, in: text)?.first else {
            return nil
        }
        let numbers = allMatches(#"\d+"#, in: segment).compactMap { Int($0) }.filter { $0 > 0 }
        guard numbers.count >= 2 else { return nil }
        return Array(Set(numbers)).sorted()
    }

    /// "alle 30 minuten ... 4x" → [30, 60, 90, 120]; without an explicit
    /// repeat count, the interval repeats for as long as the parent step's
    /// duration allows.
    private static func intervalOffsets(in text: String, totalDuration: Int) -> [Int] {
        guard let intervalText = captures(#"alle\s+(\d+)\s*minuten"#, in: text)?.first,
              let interval = Int(intervalText), interval > 0 else {
            return []
        }
        let explicitCount = captures(#"(\d+)\s*(?:x|mal)\b"#, in: text)
            .flatMap { Int($0[0]) }
        let count = explicitCount ?? totalDuration / interval
        guard count > 0 else { return [] }
        return (1...count).map { $0 * interval }
    }

    // MARK: - Text helpers

    private static func parsedDuration(in text: String) -> Int {
        guard let values = captures(#"(\d+(?:[.,]\d+)?|eine?r?|einer|einem)\s*(Min(?:ute)?n?|mn|Std\.?|Stunden?|heures?|h)\b"#, in: text) else {
            return 0
        }
        let number = normalized(values[0])
        let value = ["ein", "eine", "einer", "einem"].contains(number)
            ? 1
            : Double(values[0].replacingOccurrences(of: ",", with: ".")) ?? 0
        let unit = normalized(values[1])
        return Int((unit.hasPrefix("std") || unit == "h" || unit.hasPrefix("stunde") || unit.hasPrefix("heure")) ? value * 60 : value)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
}
