//
//  TimedFoldExpansion.swift
//  BackPlaner
//
//  Turns one imported instruction that describes repeated stretch-and-folds
//  during a rest or rise into one generated step per fold, each carrying the
//  remaining duration of the parent step from that point on. Recognises an
//  explicit list of offsets ("nach 30, 60 und 90 Minuten") and an interval
//  with an optional repeat count ("alle 30 Minuten falten, 4x"); without an
//  explicit count, the interval repeats for as long as the parent step's
//  duration allows. Shared by every import parser (GeneralRecipeParser,
//  TwoColumnRecipeParser, RecipeWebPageLoader) so the recognised wording
//  doesn't depend on where the recipe came from.
//

import Foundation

enum TimedFoldExpansion {

    static func expand(_ instructions: inout [InstructionFB]) {
        guard let foldIndex = instructions.firstIndex(where: isFoldCandidate) else { return }

        let foldInstruction = instructions[foldIndex]
        let foldText = normalized(foldInstruction.instruction)

        guard let parentIndex = parentStepIndex(for: foldText, foldIndex: foldIndex, in: instructions) else {
            return
        }

        let parent = instructions[parentIndex]
        let totalDuration = max(parent.duration, parsedDuration(in: parent.instruction))
        guard totalDuration > 0 else { return }

        let offsets = foldOffsets(in: foldText, totalDuration: totalDuration)
        guard !offsets.isEmpty else { return }

        parent.duration = totalDuration

        let foldSteps = offsets.enumerated().map { index, offset -> InstructionFB in
            let step = InstructionFB()
            step.id = UUID().uuidString
            step.step = parent.step + 0.1 * Double(index + 1)
            step.instruction = "Teig dehnen und falten (nach \(offset) Minuten)."
            step.duration = totalDuration - offset
            return step
        }

        if foldIndex == parentIndex {
            instructions.insert(contentsOf: foldSteps, at: parentIndex + 1)
        } else {
            let removedStep = foldInstruction.step
            instructions.remove(at: foldIndex)
            instructions.insert(contentsOf: foldSteps, at: parentIndex + 1)
            for instruction in instructions where instruction.step >= removedStep {
                instruction.step -= 1
            }
        }
    }

    // MARK: - Detection

    private static func isFoldCandidate(_ instruction: InstructionFB) -> Bool {
        let value = normalized(instruction.instruction)
        guard value.contains("dehnen") || value.contains("denen") else { return false }
        guard value.contains("falten") else { return false }
        return value.contains("nach ") || value.contains("alle ")
    }

    /// The fold line itself names its own rest when it already states the
    /// duration ("... 12 Stunden ruhen lassen. Dabei nach 30 und 60 Minuten
    /// falten."); otherwise the most recent preceding rest/rise step is the
    /// one the folds happen during.
    private static func parentStepIndex(
        for foldText: String, foldIndex: Int, in instructions: [InstructionFB]
    ) -> Int? {
        if foldText.contains("stunden") && foldText.contains("ruhen lassen") {
            return foldIndex
        }
        return instructions[..<foldIndex].lastIndex(where: {
            let value = normalized($0.instruction)
            return value.contains("stunden")
                && (value.contains("ruhen lassen") || value.contains("reifen lassen"))
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

    /// "nach 30, 60 und 90 minuten" → [30, 60, 90]. Requires at least two
    /// offsets to survive — a single "nach 30 minuten" reads more like a
    /// one-off timing note than a fold schedule, and a single repeated fold
    /// time is already covered by the interval pattern below.
    private static func explicitOffsets(in text: String) -> [Int]? {
        guard let segment = captures(#"nach\s+(.+?)\s*minuten"#, in: text)?.first else {
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
