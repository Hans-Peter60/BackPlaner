//
//  KitchenVoiceCommandsTests.swift
//  BakePlannerCoreTests
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Cook mode: spoken commands and spoken words")
struct KitchenVoiceCommandsTests {

    @Test("German commands: the last words count, accents and punctuation do not, the longer phrase wins")
    func german() {
        #expect(CookVoiceCommands.command(in: "Okay, erledigt.", languageCode: "de") == .done)
        #expect(CookVoiceCommands.command(in: "so der Reis steht", languageCode: "de") == .potOn)
        #expect(CookVoiceCommands.command(in: "ist im Ofen", languageCode: "de") == .potOn)
        #expect(CookVoiceCommands.command(in: "das war falsch, rückgängig", languageCode: "de") == .undo)
        #expect(CookVoiceCommands.command(in: "lies vor", languageCode: "de") == .read)
        #expect(CookVoiceCommands.command(in: "und was kommt jetzt", languageCode: "de") == .next)
        #expect(CookVoiceCommands.command(in: "weiter", languageCode: "de") == .next)
        #expect(CookVoiceCommands.command(in: "weiter machen", languageCode: "de") == .resume)
        #expect(CookVoiceCommands.command(in: "Pause", languageCode: "de") == .pause)
        #expect(CookVoiceCommands.command(in: "wie lange noch", languageCode: "de") == nil)
        #expect(CookVoiceCommands.command(in: "wie lange", languageCode: "de") == .timing)
        #expect(CookVoiceCommands.command(in: "die Zutaten", languageCode: "de") == .ingredients)
        #expect(CookVoiceCommands.command(in: "erledigt habe ich gestern schon alles", languageCode: "de") == nil)
        #expect(CookVoiceCommands.command(in: "", languageCode: "de") == nil)
    }

    @Test("English and French have their own words; an unknown language falls back to German")
    func otherLanguages() {
        #expect(CookVoiceCommands.command(in: "okay it's on", languageCode: "en") == .potOn)
        #expect(CookVoiceCommands.command(in: "what's next", languageCode: "en-GB") == .next)
        #expect(CookVoiceCommands.command(in: "carry on", languageCode: "en") == .resume)
        #expect(CookVoiceCommands.command(in: "c'est parti", languageCode: "fr") == .potOn)
        #expect(CookVoiceCommands.command(in: "et après", languageCode: "fr-CA") == .next)
        #expect(CookVoiceCommands.command(in: "erledigt", languageCode: "it") == .done)
        #expect(CookVoiceCommands.hintWords(languageCode: "en").count == 4)
    }

    @Test("Units are spelled out for the ear, unknown ones stay, and the line reads like speech")
    func spokenUnits() {
        #expect(KitchenSpokenText.spokenUnit("EL", languageCode: "de") == "Esslöffel")
        #expect(KitchenSpokenText.spokenUnit("g", languageCode: "en") == "grams")
        #expect(KitchenSpokenText.spokenUnit("Zweige", languageCode: "de") == "Zweige")
        let butter = KitchenIngredient(id: "b", name: "Butter", amount: 30, unit: "g", component: "", note: "kalt")
        #expect(KitchenSpokenText.line(for: butter, locale: Locale(identifier: "de_DE")) == "30 Gramm Butter (kalt)")
        let garlic = KitchenIngredient(id: "k", name: "Knoblauchzehe", amount: 1, component: "")
        #expect(KitchenSpokenText.lines(for: [butter, garlic], locale: Locale(identifier: "de_DE")) == "30 Gramm Butter (kalt). 1 Knoblauchzehe")
    }
}
