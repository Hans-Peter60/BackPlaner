//
//  BakeVoiceCommandsTests.swift
//  BakePlannerCoreTests
//

import Testing
@testable import BakePlannerCore

@Suite("Voice commands of the hands-free bake mode")
struct BakeVoiceCommandsTests {

    @Test("German commands are read from the end of what was said")
    func german() {
        #expect(BakeVoiceCommands.command(in: "weiter", languageCode: "de") == .next)
        #expect(BakeVoiceCommands.command(in: "Okay, weiter.", languageCode: "de") == .next)
        #expect(BakeVoiceCommands.command(in: "Nächster Schritt", languageCode: "de") == .next)
        #expect(BakeVoiceCommands.command(in: "und zurück", languageCode: "de_DE") == .previous)
        #expect(BakeVoiceCommands.command(in: "Erledigt", languageCode: "de") == .done)
        #expect(BakeVoiceCommands.command(in: "So, fertig!", languageCode: "de") == .done)
        #expect(BakeVoiceCommands.command(in: "Lies vor", languageCode: "de") == .read)
        #expect(BakeVoiceCommands.command(in: "noch mal", languageCode: "de") == .read)
        #expect(BakeVoiceCommands.command(in: "Zutaten", languageCode: "de") == .ingredients)
        #expect(BakeVoiceCommands.command(in: "Wie lange", languageCode: "de") == .timing)
        #expect(BakeVoiceCommands.command(in: "Stopp", languageCode: "de") == .stop)
    }

    @Test("English and French have their own words")
    func englishAndFrench() {
        #expect(BakeVoiceCommands.command(in: "next step", languageCode: "en_GB") == .next)
        #expect(BakeVoiceCommands.command(in: "go back", languageCode: "en") == .previous)
        #expect(BakeVoiceCommands.command(in: "Done.", languageCode: "en") == .done)
        #expect(BakeVoiceCommands.command(in: "read it", languageCode: "en") == .read)
        #expect(BakeVoiceCommands.command(in: "how long", languageCode: "en") == .timing)
        #expect(BakeVoiceCommands.command(in: "Étape suivante", languageCode: "fr") == .next)
        #expect(BakeVoiceCommands.command(in: "retour", languageCode: "fr_CA") == .previous)
        #expect(BakeVoiceCommands.command(in: "Terminé", languageCode: "fr") == .done)
        #expect(BakeVoiceCommands.command(in: "Répète", languageCode: "fr") == .read)
        #expect(BakeVoiceCommands.command(in: "combien de temps", languageCode: "fr") == .timing)
    }

    @Test("A command mentioned in passing, or nothing at all, triggers nothing")
    func noCommand() {
        #expect(BakeVoiceCommands.command(in: "", languageCode: "de") == nil)
        #expect(BakeVoiceCommands.command(in: "Den Teig weiter kneten bis er glatt ist", languageCode: "de") == nil)
        #expect(BakeVoiceCommands.command(in: "weiter", languageCode: "en") == nil)
        #expect(BakeVoiceCommands.command(in: "Brot", languageCode: "de") == nil)
    }

    @Test("The hint names the four everyday words in the plan's language")
    func hints() {
        #expect(BakeVoiceCommands.hintWords(languageCode: "de") == ["Weiter", "Zurück", "Erledigt", "Vorlesen"])
        #expect(BakeVoiceCommands.hintWords(languageCode: "fr") == ["Suivant", "Retour", "Terminé", "Lire"])
        #expect(BakeVoiceCommands.hintWords(languageCode: "it").first == "Weiter")
    }
}
