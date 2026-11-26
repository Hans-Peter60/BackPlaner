//
//  KitchenVoiceCommands.swift
//  BakePlannerCore
//
//  The spoken commands of CookPlanner's cook mode and how a transcript is
//  read for them — the same way as BakePlanner's (BakeVoiceCommands), with
//  the cook's own words: a pot is "put on", a tick is taken back.
//  Listening and speaking are the app's job; only the words live here.
//

import Foundation

/// What the cook can say to the cook mode.
public enum CookVoiceCommand: String, CaseIterable, Sendable {
    /// "Erledigt" — the step in the hands is done.
    case done
    /// "Steht" — the pot is on, the oven door shut: its time runs from now.
    case potOn
    /// "Zurück" — the last tick is taken back.
    case undo
    /// "Vorlesen" — read the current step again.
    case read
    /// "Was kommt" — read the next step.
    case next
    /// "Zutaten" — read the current step's ingredients.
    case ingredients
    /// "Wie lange" — the time left on the step and on the clock.
    case timing
    /// "Pause" — stop the clock.
    case pause
    /// "Weitermachen" — the clock runs again.
    case resume
    /// "Stopp" — stop talking.
    case stop
}

public enum CookVoiceCommands {

    /// The words that trigger each command, per base language. Longer
    /// phrases are matched as wholes, so "weiter machen" is not read as a
    /// stray "weiter".
    static func phrases(languageCode: String) -> [(CookVoiceCommand, [String])] {
        switch AppSettings.baseLanguage(of: languageCode) {
        case "en":
            return [
                (.resume, ["carry on", "continue", "go on", "unpause"]),
                (.done, ["done", "finished", "complete", "check"]),
                (.potOn, ["it's on", "its on", "pot is on", "in the oven", "put on", "started", "simmering"]),
                (.undo, ["undo", "take back", "go back", "back"]),
                (.read, ["read aloud", "read it", "read", "repeat", "again"]),
                (.next, ["what's next", "whats next", "next step", "coming up", "next"]),
                (.ingredients, ["ingredients"]),
                (.timing, ["how long", "how much time", "time left", "when"]),
                (.pause, ["pause", "hold on"]),
                (.stop, ["stop", "quiet"]),
            ]
        case "fr":
            return [
                (.resume, ["on continue", "continuer", "reprendre", "reprends"]),
                (.done, ["termine", "terminee", "fini", "fait", "c'est fait", "cest fait"]),
                (.potOn, ["c'est parti", "cest parti", "sur le feu", "au four", "ca cuit", "lance", "lancee"]),
                (.undo, ["annuler", "annule", "retour", "en arriere"]),
                (.read, ["lire", "relis", "repete", "repeter", "encore"]),
                (.next, ["et apres", "etape suivante", "la suite", "suivant", "suivante"]),
                (.ingredients, ["ingredients"]),
                (.timing, ["combien de temps", "temps restant", "quand"]),
                (.pause, ["pause"]),
                (.stop, ["stop", "arrete", "silence"]),
            ]
        default:
            return [
                (.resume, ["weiter machen", "weitermachen", "fortsetzen", "weiter geht's", "weiter gehts"]),
                (.done, ["erledigt", "fertig", "abhaken", "gemacht"]),
                (.potOn, ["steht", "aufgesetzt", "auf dem herd", "im ofen", "lauft", "kocht", "drin", "ist drin"]),
                (.undo, ["ruckgangig", "zuruck", "zurucknehmen"]),
                (.read, ["lies vor", "vorlesen", "nochmal", "noch mal", "wiederholen"]),
                (.next, ["was kommt", "was kommt jetzt", "nachster schritt", "gleich", "weiter"]),
                (.ingredients, ["zutaten"]),
                (.timing, ["wie lange", "wie viel zeit", "wieviel zeit", "wie spat", "uhr"]),
                (.pause, ["pause"]),
                (.stop, ["stopp", "stop", "ruhe"]),
            ]
        }
    }

    /// The command the transcript ends with, or nil. Case, accents and
    /// punctuation do not count; "Okay, erledigt." is `.done`. The longest
    /// matching phrase wins, so "weiter machen" is `.resume`, not `.next`.
    public static func command(in transcript: String, languageCode: String) -> CookVoiceCommand? {
        let words = BakeVoiceCommands.normalizedWords(transcript)
        guard !words.isEmpty else { return nil }
        let tail = Array(words.suffix(BakeVoiceCommands.trailingWords))
        var best: (command: CookVoiceCommand, length: Int)?
        for (command, variants) in phrases(languageCode: languageCode) {
            for phrase in variants {
                let phraseWords = BakeVoiceCommands.normalizedWords(phrase)
                guard tail.count >= phraseWords.count, Array(tail.suffix(phraseWords.count)) == phraseWords else { continue }
                if best == nil || phraseWords.count > best!.length {
                    best = (command, phraseWords.count)
                }
            }
        }
        return best?.command
    }

    /// The words the cook can say, for the hint on screen and the spoken
    /// introduction: the four everyday commands in the app's language.
    public static func hintWords(languageCode: String) -> [String] {
        switch AppSettings.baseLanguage(of: languageCode) {
        case "en": return ["Done", "It's on", "Read", "What's next"]
        case "fr": return ["Terminé", "C'est parti", "Lire", "Et après"]
        default:   return ["Erledigt", "Steht", "Vorlesen", "Was kommt"]
        }
    }
}

/// Words for the ear: "EL" on screen is "Esslöffel" when read aloud.
public enum KitchenSpokenText {

    static func spokenUnits(languageCode: String) -> [String: String] {
        switch AppSettings.baseLanguage(of: languageCode) {
        case "en":
            return ["g": "grams", "kg": "kilograms", "ml": "millilitres", "l": "litres", "cl": "centilitres",
                    "tbsp": "tablespoons", "tsp": "teaspoons", "pc": "pieces", "pcs": "pieces", "oz": "ounces",
                    "lb": "pounds", "lbs": "pounds", "fl oz": "fluid ounces", "pkg": "packs"]
        case "fr":
            return ["g": "grammes", "kg": "kilogrammes", "ml": "millilitres", "l": "litres", "cl": "centilitres",
                    "c. à s.": "cuillères à soupe", "c. à c.": "cuillères à café", "cs": "cuillères à soupe",
                    "cc": "cuillères à café", "pc": "pièces", "sachet": "sachet"]
        default:
            return ["g": "Gramm", "kg": "Kilogramm", "ml": "Milliliter", "l": "Liter", "cl": "Zentiliter",
                    "el": "Esslöffel", "tl": "Teelöffel", "msp": "Messerspitze", "msp.": "Messerspitze",
                    "stk": "Stück", "stk.": "Stück", "st": "Stück", "st.": "Stück", "pck": "Päckchen",
                    "pck.": "Päckchen", "pkg": "Packung", "bd": "Bund", "ztr": "Zentner"]
        }
    }

    /// The unit as one says it; unknown units stay as written.
    public static func spokenUnit(_ unit: String, languageCode: String) -> String {
        let key = unit.trimmingCharacters(in: .whitespaces).lowercased()
        return spokenUnits(languageCode: languageCode)[key] ?? unit
    }

    /// An ingredient line for reading aloud: "30 Gramm Butter", "2 Esslöffel Öl (kalt)".
    public static func line(for ingredient: KitchenIngredient, locale: Locale) -> String {
        let spokenIngredient = KitchenIngredient(id: ingredient.id, name: ingredient.name, amount: ingredient.amount,
                                                 unit: spokenUnit(ingredient.unit, languageCode: locale.identifier),
                                                 component: ingredient.component, note: ingredient.note)
        return spokenIngredient.line(locale: locale)
    }

    /// Several ingredients as one sentence: "30 Gramm Butter. 1 Knoblauchzehe."
    public static func lines(for ingredients: [KitchenIngredient], locale: Locale) -> String {
        ingredients.map { line(for: $0, locale: locale) }.joined(separator: ". ")
    }
}
