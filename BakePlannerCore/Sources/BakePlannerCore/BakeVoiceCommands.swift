//
//  BakeVoiceCommands.swift
//  BakePlannerCore
//
//  The spoken commands of the hands-free bake mode and how a transcript is
//  read for them. Only the words matter here; listening is the app's job.
//

import Foundation

/// What the baker can say to the bake mode.
public enum BakeVoiceCommand: String, CaseIterable, Sendable {
    /// "Weiter" — the next step.
    case next
    /// "Zurück" — the step before.
    case previous
    /// "Erledigt" — the step is done and leaves the plan.
    case done
    /// "Vorlesen" — read the step aloud again.
    case read
    /// "Zutaten" — read only the ingredients.
    case ingredients
    /// "Wie lange" — when the step is due.
    case timing
    /// "Stopp" — stop talking.
    case stop
}

public enum BakeVoiceCommands {

    /// The words that trigger each command, per base language. Longer
    /// phrases first, so "nächster Schritt" is not read as a stray "Schritt".
    static func phrases(languageCode: String) -> [(BakeVoiceCommand, [String])] {
        switch AppSettings.baseLanguage(of: languageCode) {
        case "en":
            return [
                (.next, ["next step", "next"]),
                (.previous, ["previous step", "go back", "previous", "back"]),
                (.done, ["done", "finished", "complete"]),
                (.read, ["read aloud", "read it", "read", "repeat", "again"]),
                (.ingredients, ["ingredients"]),
                (.timing, ["how long", "how much time", "when"]),
                (.stop, ["stop", "quiet"]),
            ]
        case "fr":
            return [
                (.next, ["etape suivante", "suivant", "suivante"]),
                (.previous, ["etape precedente", "precedent", "precedente", "retour"]),
                (.done, ["termine", "terminee", "fini", "fait"]),
                (.read, ["lire", "relis", "repete", "repeter", "encore"]),
                (.ingredients, ["ingredients"]),
                (.timing, ["combien de temps", "quand"]),
                (.stop, ["stop", "arrete", "silence"]),
            ]
        default:
            return [
                (.next, ["nachster schritt", "weiter", "nachster"]),
                (.previous, ["vorheriger schritt", "zuruck"]),
                (.done, ["erledigt", "fertig", "abhaken"]),
                (.read, ["lies vor", "vorlesen", "nochmal", "noch mal", "wiederholen"]),
                (.ingredients, ["zutaten"]),
                (.timing, ["wie lange", "wann"]),
                (.stop, ["stopp", "stop", "ruhe"]),
            ]
        }
    }

    /// How many words from the end of the transcript are looked at: a
    /// command is what the baker says last, not something mentioned in
    /// passing a sentence ago.
    static let trailingWords = 3

    /// The command the transcript ends with, or nil. Case, accents and
    /// punctuation do not count; "Okay, weiter." is `.next`.
    public static func command(in transcript: String, languageCode: String) -> BakeVoiceCommand? {
        let words = normalizedWords(transcript)
        guard !words.isEmpty else { return nil }
        let tail = Array(words.suffix(trailingWords))
        for (command, variants) in phrases(languageCode: languageCode) {
            for phrase in variants {
                let phraseWords = phrase.split(separator: " ").map(String.init)
                if tail.count >= phraseWords.count,
                   Array(tail.suffix(phraseWords.count)) == phraseWords {
                    return command
                }
            }
        }
        return nil
    }

    /// The words the baker can say, for the hint on screen and the spoken
    /// introduction: the four everyday commands in the plan's language.
    public static func hintWords(languageCode: String) -> [String] {
        switch AppSettings.baseLanguage(of: languageCode) {
        case "en": return ["Next", "Back", "Done", "Read"]
        case "fr": return ["Suivant", "Retour", "Terminé", "Lire"]
        default:   return ["Weiter", "Zurück", "Erledigt", "Vorlesen"]
        }
    }

    /// Lowercase words without accents or punctuation.
    static func normalizedWords(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
        return folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
