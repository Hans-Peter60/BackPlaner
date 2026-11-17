//
//  BakePlanSimulationTests.swift
//  BakePlannerCoreTests
//
//  Twenty complex recipes — multi-stage sourdoughs, scalds and soakers in
//  parallel, preferments, cold retards, several baking phases, a starter
//  feeding, a stollen that ripens for weeks — planned the way the app
//  plans them: start times from `Rational.calculateStartTimes` with the
//  component dependencies, the plan from `BakePlan` in "Fertig bis" mode,
//  the hints from `BakePlanValidator`, the suggestions from
//  `BakePlanAdvisor`. The test checks the invariants every plan has to keep
//  and writes the full schedules to /tmp/bakeplan-simulation.md for a
//  reading by eye, which is where plausibility is judged.
//

import Foundation
import Testing
@testable import BakePlannerCore

@Suite("Bake planning: twenty complex recipes simulated", .serialized)
struct BakePlanSimulationTests {

    // MARK: - Recipe model of the simulation

    struct Step {
        let step: Double
        let text: String
        let minutes: Int
        var component: String? = nil
        var window: ClosedRange<Int>? = nil
        var oven: OvenSettings? = nil
    }

    struct Component {
        let name: String
        /// Other components this one uses up ("gesamte …" rows without weight).
        var uses: [String] = []
    }

    struct Recipe {
        let name: String
        let language: String
        let components: [Component]
        let steps: [Step]
        /// The start of the step that is expected to be the bake, nil for
        /// a recipe without a bake.
        let expectedBake: String?
        var isStarterFeeding: Bool = false
        /// Minutes the oven is expected to be switched on before the bake
        /// (nil when the recipe has its own preheating step or a cold oven).
        var expectedPreheat: Int? = 15
    }

    private func S(_ step: Double, _ text: String, _ minutes: Int, c: String? = nil,
                   w: ClosedRange<Int>? = nil, oven: OvenSettings? = nil) -> Step {
        Step(step: step, text: text, minutes: minutes, component: c, window: w, oven: oven)
    }

    // MARK: - The twenty recipes

    private var recipes: [Recipe] {
        [
            Recipe(name: "1 Rauriser Roggenbrot (zwei Sauerteigstufen, Brühstück)", language: "de",
                   components: [Component(name: "Sauerteig Stufe 1"),
                                Component(name: "Sauerteig Stufe 2", uses: ["Sauerteig Stufe 1"]),
                                Component(name: "Brühstück"),
                                Component(name: "Hauptteig", uses: ["Sauerteig Stufe 2", "Brühstück"])],
                   steps: [S(1.1, "Sauerteig Stufe 1 ansetzen und bei 26 °C reifen lassen", 720, c: "Sauerteig Stufe 1"),
                           S(1.2, "Sauerteig Stufe 2 mit der gesamten Stufe 1 ansetzen, 3 Stunden bei 28 °C", 180, c: "Sauerteig Stufe 2"),
                           S(1.3, "Brühstück: Roggenschrot mit kochendem Wasser übergießen, über Nacht quellen lassen", 720, c: "Brühstück"),
                           S(2, "Hauptteig aus Sauerteig, Brühstück, Mehl, Wasser und Salz 8 Minuten mischen", 10, c: "Hauptteig"),
                           S(3, "Teigruhe 30 Minuten", 30),
                           S(4, "Rund wirken und mit Schluss nach oben ins Gärkörbchen setzen", 10),
                           S(5, "Stückgare 60–75 Minuten bei Raumtemperatur", 70, w: 60...75),
                           S(6, "Bei 250 °C fallend auf 210 °C 60 Minuten mit Dampf backen", 60,
                             oven: OvenSettings(temperature: 250, fallingTo: 210, steam: true)),
                           S(7, "Auf einem Gitter auskühlen lassen", 60)],
                   expectedBake: "Bei 250 °C"),

            Recipe(name: "2 Baguette mit Poolish (Falten während der Stockgare)", language: "de",
                   components: [Component(name: "Poolish"), Component(name: "Hauptteig", uses: ["Poolish"])],
                   steps: [S(1, "Poolish ansetzen und 12 Stunden bei Raumtemperatur reifen lassen", 720, c: "Poolish", w: 600...840),
                           S(2, "Autolyse: Mehl und Wasser mischen, 30 Minuten ruhen lassen", 30, c: "Hauptteig"),
                           S(3, "Poolish, Salz und Hefe einarbeiten, 8 Minuten kneten", 10),
                           S(4.1, "Stockgare 120 Minuten bei 24 °C", 120),
                           S(4.2, "Nach 30 Minuten dehnen und falten", 90),
                           S(4.3, "Nach 60 Minuten dehnen und falten", 60),
                           S(4.4, "Nach 90 Minuten dehnen und falten", 30),
                           S(5, "Teiglinge abstechen und vorformen, 20 Minuten entspannen lassen", 25),
                           S(6, "Baguettes formen und im Bäckerleinen 45 Minuten gehen lassen", 50),
                           S(7, "Backofen mit Backstein auf 250 °C vorheizen", 45),
                           S(8, "Einschneiden, auf den heißen Stein einschießen und 22 Minuten mit Schwaden backen", 22),
                           S(9, "Auskühlen lassen", 20)],
                   expectedBake: "Einschneiden", expectedPreheat: nil),

            Recipe(name: "3 Country loaf (Tartine style, cold retard, Dutch oven)", language: "en",
                   components: [Component(name: "Levain"), Component(name: "Dough", uses: ["Levain"])],
                   steps: [S(1, "Mix the levain and let it ripen 10 to 12 hours", 660, c: "Levain", w: 600...720),
                           S(2, "Autolyse: mix flour and water, rest 40 minutes", 40, c: "Dough"),
                           S(3, "Add levain and salt, mix by hand", 15),
                           S(4.1, "Bulk fermentation 4 hours at 26 °C", 240),
                           S(4.2, "Stretch and fold after 30 minutes", 210),
                           S(4.3, "Stretch and fold after 60 minutes", 180),
                           S(4.4, "Coil fold after 2 hours", 120),
                           S(5, "Pre-shape and bench rest", 30),
                           S(6, "Final shape, into the banneton", 10),
                           S(7, "Cold retard in the fridge overnight", 720, w: 600...960),
                           S(8, "Preheat the oven with the Dutch oven inside to 250 °C", 45),
                           S(9, "Score and bake in the preheated Dutch oven, lid on, 20 minutes", 20,
                             oven: OvenSettings(temperature: 250, fallingTo: nil, steam: nil)),
                           S(10, "Remove the lid and bake at 230 °C for another 25 minutes", 25,
                             oven: OvenSettings(temperature: 230, fallingTo: nil, steam: nil)),
                           S(11, "Check the core temperature (96 °C) and cool on a rack", 90)],
                   expectedBake: "Score and bake", expectedPreheat: nil),

            Recipe(name: "4 Pain de campagne (levain, apprêt au froid)", language: "fr",
                   components: [Component(name: "Levain"), Component(name: "Pâte", uses: ["Levain"])],
                   steps: [S(1, "Rafraîchir le levain et le laisser mûrir 8 heures", 480, c: "Levain"),
                           S(2, "Pétrir la pâte avec le levain", 15, c: "Pâte"),
                           S(3, "Pointage 3 heures avec deux rabats", 180),
                           S(4, "Façonner et mettre en banneton", 15),
                           S(5, "Apprêt au réfrigérateur 14 heures", 840),
                           S(6, "Préchauffer le four à 250 °C", 40),
                           S(7, "Grigner et cuire 45 minutes, les 15 premières avec buée", 45,
                             oven: OvenSettings(temperature: 250, fallingTo: 230, steam: true)),
                           S(8, "Laisser refroidir sur grille", 60)],
                   expectedBake: "Grigner", expectedPreheat: nil),

            Recipe(name: "5 Ciabatta mit Biga (Dampf ablassen als eigener Schritt)", language: "de",
                   components: [Component(name: "Biga"), Component(name: "Hauptteig", uses: ["Biga"])],
                   steps: [S(1, "Biga fest kneten und 16 Stunden bei 18 °C reifen lassen", 960, c: "Biga"),
                           S(2, "Hauptteig: Biga mit Wasser, Mehl, Hefe und Salz 12 Minuten kneten", 15, c: "Hauptteig"),
                           S(3.1, "Stockgare 90 Minuten", 90),
                           S(3.2, "Nach 30 Minuten falten", 60),
                           S(3.3, "Nach 60 Minuten falten", 30),
                           S(4, "Teig auf die bemehlte Arbeitsfläche kippen, in vier Stücke teilen", 10),
                           S(5, "Stückgare 45 Minuten im Bäckerleinen", 45),
                           S(6, "Mit Dampf bei 240 °C fallend auf 220 °C 25 Minuten backen", 25),
                           S(7, "Nach 10 Minuten Dampf ablassen", 1),
                           S(8, "Auskühlen lassen", 30)],
                   expectedBake: "Mit Dampf"),

            Recipe(name: "6 Dinkelvollkornbrot mit Kochstück (kalter Ofen)", language: "de",
                   components: [Component(name: "Kochstück"), Component(name: "Sauerteig"),
                                Component(name: "Hauptteig", uses: ["Kochstück", "Sauerteig"])],
                   steps: [S(1.1, "Kochstück: Mehl und Wasser unter Rühren aufkochen, abdecken und über Nacht auskühlen lassen", 720, c: "Kochstück"),
                           S(1.2, "Sauerteig ansetzen, 14 Stunden bei Raumtemperatur reifen lassen", 840, c: "Sauerteig"),
                           S(2, "Hauptteig aus Kochstück, Sauerteig und den übrigen Zutaten 6 Minuten mischen", 8, c: "Hauptteig"),
                           S(3, "Stockgare 60 Minuten", 60),
                           S(4, "In die gefettete Kastenform geben, Oberfläche glatt streichen", 10),
                           S(5, "Stückgare 90 Minuten", 90),
                           S(6, "Im kalten Backofen bei 200 °C 70 Minuten backen", 70),
                           S(7, "Aus der Form nehmen und auskühlen lassen", 120)],
                   expectedBake: "Im kalten", expectedPreheat: 0),

            Recipe(name: "7 Detmolder Dreistufen-Roggenbrot (Anfrisch-, Grund-, Vollsauer)", language: "de",
                   components: [Component(name: "Anfrischsauer"),
                                Component(name: "Grundsauer", uses: ["Anfrischsauer"]),
                                Component(name: "Vollsauer", uses: ["Grundsauer"]),
                                Component(name: "Hauptteig", uses: ["Vollsauer"])],
                   steps: [S(1.1, "Anfrischsauer ansetzen, 6 Stunden bei 26 °C", 360, c: "Anfrischsauer"),
                           S(1.2, "Grundsauer mit dem gesamten Anfrischsauer ansetzen, 18 Stunden bei 23 °C", 1080, c: "Grundsauer"),
                           S(1.3, "Vollsauer mit dem gesamten Grundsauer ansetzen, 3 Stunden bei 30 °C", 180, c: "Vollsauer"),
                           S(2, "Hauptteig mischen, 10 Minuten langsam kneten", 12, c: "Hauptteig"),
                           S(3, "Teigruhe 20 Minuten", 20),
                           S(4, "Rund wirken, in den Gärkorb legen", 10),
                           S(5, "Stückgare 70 Minuten", 70),
                           S(6, "Bei 260 °C einschießen, kräftig schwaden, nach 10 Minuten auf 210 °C zurückschalten, insgesamt 75 Minuten backen", 75),
                           S(7, "Mit Wasser abstreichen und auskühlen lassen", 180)],
                   expectedBake: "Bei 260 °C"),

            Recipe(name: "8 Brioche (Vorteig, kalte Stockgare über Nacht)", language: "de",
                   components: [Component(name: "Vorteig"), Component(name: "Hauptteig", uses: ["Vorteig"])],
                   steps: [S(1, "Vorteig aus Mehl, Milch und Hefe anrühren, 60 Minuten gehen lassen", 60, c: "Vorteig"),
                           S(2, "Hauptteig 15 Minuten kneten, Butter stückweise einarbeiten", 20, c: "Hauptteig"),
                           S(3, "Stockgare 60 Minuten bei Raumtemperatur", 60),
                           S(4, "Teig flach drücken und 12 Stunden kalt stellen", 720, w: 600...1440),
                           S(5, "Teig teilen, Kugeln formen und in die Form setzen", 20),
                           S(6, "Stückgare 2 Stunden, bis sich das Volumen verdoppelt hat", 120),
                           S(7, "Mit Ei bestreichen, bei 180 °C 30 Minuten backen", 30),
                           S(8, "In der Form 10 Minuten ruhen lassen, dann auskühlen", 40)],
                   expectedBake: "Mit Ei"),

            Recipe(name: "9 Pizza napoletana (24 Stunden kalte Ballengare, Backstein)", language: "de",
                   components: [Component(name: "Teig")],
                   steps: [S(1, "Teig kneten, Teigtemperatur 23 °C", 15, c: "Teig"),
                           S(2, "Stockgare 2 Stunden bei Raumtemperatur", 120),
                           S(3, "Ballen zu je 250 g formen", 15),
                           S(4, "Ballengare 24 Stunden im Kühlschrank", 1440),
                           S(5, "Ballen 2 Stunden akklimatisieren lassen", 120),
                           S(6, "Backofen mit Pizzastein auf 275 °C vorheizen", 60),
                           S(7, "Pizza ausziehen, belegen und auf dem Stein 7 Minuten backen", 7),
                           S(8, "Sofort servieren", 0)],
                   expectedBake: "Pizza ausziehen", expectedPreheat: nil),

            Recipe(name: "10 Weizensauerteigbrot mit drei Sauerteigen (parallel)", language: "de",
                   components: [Component(name: "Weizensauer"), Component(name: "Roggensauer"),
                                Component(name: "Lievito madre"),
                                Component(name: "Hauptteig", uses: ["Weizensauer", "Roggensauer", "Lievito madre"])],
                   steps: [S(1.1, "Weizensauer ansetzen, 12 Stunden bei 24 °C", 720, c: "Weizensauer"),
                           S(1.2, "Roggensauer ansetzen, 14 Stunden bei 24 °C", 840, c: "Roggensauer"),
                           S(1.3, "Lievito madre auffrischen, 4 Stunden bei 28 °C", 240, c: "Lievito madre"),
                           S(2, "Hauptteig 12 Minuten kneten", 14, c: "Hauptteig"),
                           S(3.1, "Stockgare 3 Stunden", 180),
                           S(3.2, "Nach 45 Minuten falten", 135),
                           S(3.3, "Nach 90 Minuten falten", 90),
                           S(4, "Lang wirken, ins Gärkörbchen", 15),
                           S(5, "Stückgare 60 Minuten, dann 30 Minuten in den Kühlschrank", 90),
                           S(6, "Bei 250 °C fallend auf 220 °C 50 Minuten mit Schwaden backen", 50),
                           S(7, "Auskühlen lassen", 90)],
                   expectedBake: "Bei 250 °C"),

            Recipe(name: "11 Vinschgerl (Brötchen, kurze Backzeit, ohne Auskühlen)", language: "de",
                   components: [Component(name: "Sauerteig"), Component(name: "Hauptteig", uses: ["Sauerteig"])],
                   steps: [S(1, "Sauerteig ansetzen, 16 Stunden", 960, c: "Sauerteig"),
                           S(2, "Hauptteig mit Brotgewürz mischen", 10, c: "Hauptteig"),
                           S(3, "Teigruhe 45 Minuten", 45),
                           S(4, "Teiglinge abstechen, in Roggenmehl wälzen und flach drücken", 15),
                           S(5, "Stückgare 40 Minuten", 40),
                           S(6, "Bei 240 °C 18 Minuten backen", 18)],
                   expectedBake: "Bei 240 °C"),

            Recipe(name: "12 Panettone (two doughs over two days, hung to cool)", language: "en",
                   components: [Component(name: "First dough"), Component(name: "Second dough", uses: ["First dough"])],
                   steps: [S(1, "Mix the first dough with the refreshed lievito madre", 25, c: "First dough"),
                           S(2, "Let the first dough triple, about 12 hours at 26 °C", 720, w: 600...840),
                           S(3, "Mix the second dough, adding butter, yolks, candied fruit", 40, c: "Second dough"),
                           S(4, "Rest 60 minutes, shape and place in the paper mould", 70),
                           S(5, "Final proof 6 hours at 28 °C until the dome reaches the rim", 360, w: 300...480),
                           S(6, "Score, place the butter, bake at 170 °C for 50 minutes", 50),
                           S(7, "Hang upside down on skewers and cool for 12 hours", 720)],
                   expectedBake: "Score, place"),

            Recipe(name: "13 Knäckebrot (zwei Backphasen: backen, dann trocknen)", language: "de",
                   components: [Component(name: "Teig")],
                   steps: [S(1, "Saaten, Mehl, Salz, Öl und Wasser verrühren, 30 Minuten quellen lassen", 35, c: "Teig"),
                           S(2, "Dünn auf zwei Bleche streichen und in Rechtecke schneiden", 15),
                           S(3, "Bei 220 °C 12 Minuten backen", 12),
                           S(4, "Ofen auf 150 °C herunterschalten und 60 Minuten trocknen lassen", 60),
                           S(5, "Im ausgeschalteten Ofen bei leicht geöffneter Tür auskühlen lassen", 60)],
                   expectedBake: "Bei 220 °C"),

            Recipe(name: "14 Laugenbrezeln (kalte Reife, eigener Vorheizschritt mit Temperatur)", language: "de",
                   components: [Component(name: "Teig")],
                   steps: [S(1, "Festen Teig 10 Minuten kneten", 12, c: "Teig"),
                           S(2, "Stockgare 60 Minuten", 60),
                           S(3, "Brezeln schlingen und auf Bleche legen", 25),
                           S(4, "Unbedeckt 12 Stunden im Kühlschrank verhauten lassen", 720),
                           S(5, "Backofen auf 220 °C vorheizen", 20),
                           S(6, "Brezeln 30 Sekunden in 4%ige Natronlauge tauchen, mit Salz bestreuen und einschneiden", 15),
                           S(7, "Bei 220 °C 15 Minuten backen", 15),
                           S(8, "Auskühlen lassen", 15)],
                   expectedBake: "Bei 220 °C 15", expectedPreheat: nil),

            Recipe(name: "15 Christstollen (reift drei Wochen nach dem Backen)", language: "de",
                   components: [Component(name: "Vorteig"), Component(name: "Hauptteig", uses: ["Vorteig"])],
                   steps: [S(1, "Rosinen in Rum einlegen", 5),
                           S(2, "Vorteig aus Hefe, Milch und Mehl 30 Minuten gehen lassen", 30, c: "Vorteig"),
                           S(3, "Hauptteig mit Butter und Gewürzen kneten, Früchte unterarbeiten", 20, c: "Hauptteig"),
                           S(4, "Stockgare 60 Minuten", 60),
                           S(5, "Stollen formen, 30 Minuten gehen lassen", 40),
                           S(6, "Bei 180 °C fallend auf 160 °C nach 20 Minuten 60 Minuten backen", 60),
                           S(7, "Heiß mit zerlassener Butter bestreichen und zuckern", 15),
                           S(8, "In Alufolie gewickelt drei Wochen kühl reifen lassen", 30240)],
                   expectedBake: "Bei 180 °C"),

            Recipe(name: "16 Focaccia (72 Stunden kalte Gare)", language: "de",
                   components: [Component(name: "Teig")],
                   steps: [S(1, "Sehr weichen Teig mischen", 10, c: "Teig"),
                           S(2.1, "60 Minuten anspringen lassen", 60),
                           S(2.2, "Nach 20 Minuten falten", 40),
                           S(2.3, "Nach 40 Minuten falten", 20),
                           S(3, "72 Stunden im Kühlschrank reifen lassen", 4320, w: 2880...4320),
                           S(4, "Auf das geölte Blech geben, 2 Stunden akklimatisieren", 120),
                           S(5, "Dellen eindrücken, mit Olivenöl, Salz und Rosmarin belegen", 10),
                           S(6, "Bei 230 °C 25 Minuten backen", 25),
                           S(7, "Auskühlen lassen", 20)],
                   expectedBake: "Bei 230 °C"),

            Recipe(name: "17 Bagels (Fahrenheit, boiled before baking)", language: "en",
                   components: [Component(name: "Dough")],
                   steps: [S(1, "Knead a stiff dough for 10 minutes", 12, c: "Dough"),
                           S(2, "Bulk fermentation 90 minutes", 90),
                           S(3, "Divide, shape the rings", 20),
                           S(4, "Cold retard overnight, 12 hours", 720),
                           S(5, "Boil the bagels 1 minute per side in water with barley malt", 20),
                           S(6, "Top with seeds and bake at 450°F for 22 minutes", 22),
                           S(7, "Cool on a rack", 30)],
                   expectedBake: "Top with seeds"),

            Recipe(name: "18 Hefezopf (Gehen im ausgeschalteten Backofen)", language: "de",
                   components: [Component(name: "Teig")],
                   steps: [S(1, "Teig mit Milch, Butter, Ei und Hefe 10 Minuten kneten", 12, c: "Teig"),
                           S(2, "Teig im ausgeschalteten Backofen mit eingeschalteter Lampe 90 Minuten gehen lassen", 90),
                           S(3, "Drei Stränge rollen und zum Zopf flechten", 15),
                           S(4, "Stückgare 45 Minuten", 45),
                           S(5, "Mit Ei bestreichen, Hagelzucker aufstreuen", 5),
                           S(6, "Bei 170 °C Umluft 30 Minuten backen", 30),
                           S(7, "Auskühlen lassen", 45)],
                   expectedBake: "Bei 170 °C"),

            Recipe(name: "19 Weizenanstellgut auffrischen (kein Backen)", language: "de",
                   components: [Component(name: "Fütterung")],
                   steps: [S(1, "Anstellgut, Mehl und Wasser 1:5:5 verrühren", 5, c: "Fütterung"),
                           S(2, "Bei 26 °C reifen lassen, bis sich das Volumen verdoppelt hat (8–10 Stunden)", 540, w: 480...600),
                           S(3, "Bis zum nächsten Backen in den Kühlschrank stellen", 5)],
                   expectedBake: nil, isStarterFeeding: true, expectedPreheat: nil),

            Recipe(name: "20 Übernacht-Baguettes (16 Stunden Stockgare bei Raumtemperatur)", language: "de",
                   components: [Component(name: "Teig")],
                   steps: [S(1, "Teig mit wenig Hefe 5 Minuten mischen", 8, c: "Teig"),
                           S(2.1, "Stockgare 16 Stunden bei 20 °C", 960, w: 840...1080),
                           S(2.2, "Nach 30 Minuten falten", 930),
                           S(2.3, "Nach 60 Minuten falten", 900),
                           S(3, "Teiglinge abstechen und zu Baguettes formen", 20),
                           S(4, "Stückgare 45 Minuten", 45),
                           S(5, "Bei 250 °C mit Schwaden 22 Minuten backen, Schwaden nach 10 Minuten ablassen", 22),
                           S(6, "Auskühlen lassen", 20)],
                   expectedBake: "Bei 250 °C"),
        ]
    }

    // MARK: - Planning as the app does it

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }()

    /// Saturday, 21 November 2026, 18:00 — "Fertig bis".
    private var finish: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 18, minute: 0))!
    }

    /// The moment of planning: Tuesday morning the same week.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 9, minute: 0))!
    }

    private struct Planned {
        let recipe: Recipe
        let plan: BakePlan
        let prepTime: Int
    }

    private func plan(_ recipe: Recipe) -> Planned {
        let instructions = recipe.steps.map { step -> InstructionFB in
            let instruction = InstructionFB()
            instruction.id = UUID().uuidString
            instruction.step = step.step
            instruction.instruction = step.text
            instruction.duration = step.minutes
            instruction.componentName = step.component
            instruction.minDuration = step.window?.lowerBound
            instruction.maxDuration = step.window?.upperBound
            instruction.ovenTemperature = step.oven?.temperature
            instruction.ovenFallingTemperature = step.oven?.fallingTo
            instruction.ovenSteam = step.oven?.steam
            return instruction
        }
        let components = recipe.components.map { component -> ComponentFB in
            let componentFB = ComponentFB()
            componentFB.name = component.name
            let flour = IngredientFB()
            flour.name = "Mehl"
            flour.weight = 100
            componentFB.ingredients = [flour] + component.uses.map { used in
                let row = IngredientFB()
                row.name = "gesamte \(used)"
                row.weight = 0
                return row
            }
            return componentFB
        }
        let dependencies = Rational.ComponentDependency.from(components)
        let timed = Rational.calculateStartTimes(instructions, now, dependencies: dependencies)
        let prepTime = GlobalVariables.totalDuration
        let steps = timed.map { instruction in
            PlanStep(instruction: instruction.instruction, step: instruction.step,
                     startTime: instruction.startTime ?? 0, duration: instruction.duration,
                     componentName: instruction.componentName, durationWindow: instruction.durationWindow,
                     oven: instruction.oven)
        }
        let plan = BakePlan(recipeName: recipe.name, steps: steps, prepTime: prepTime,
                            anchor: .finishesBy, date: finish, languageCode: recipe.language,
                            preheatTime: 15, stonePreheatTime: 45, calendar: calendar,
                            isStarterFeeding: recipe.isStarterFeeding, ovenProfile: nil)
        return Planned(recipe: recipe, plan: plan, prepTime: prepTime)
    }

    // MARK: - Report

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "EEE dd.MM. HH:mm"
        return formatter.string(from: date)
    }

    private func report(_ planned: Planned) -> String {
        let plan = planned.plan
        var lines: [String] = []
        lines.append("## \(planned.recipe.name)")
        lines.append("Gesamt \(Rational.displayHoursMinutes(plan.totalMinutes)) (prepTime \(planned.prepTime)) · Start \(timeText(plan.baseDate)) · Fertig \(timeText(plan.date(of: plan.endStep)))")
        if let bake = plan.bakingStep {
            lines.append("Backschritt: „\(bake.instruction)“ · Vorheizen \(plan.preheatDuration) min · Stein: \(plan.usesBakingStone) · Ofentemperatur: \(plan.ovenTemperature ?? "–")")
        } else {
            lines.append("Kein Backschritt (Fütterung: \(plan.isStarterFeeding))")
        }
        lines.append("")
        lines.append("| Zeit | Nr. | Dauer | Schritt |")
        lines.append("|---|---|---|---|")
        let ordered = plan.allSteps.sorted { ($0.startTime, $0.step) < ($1.startTime, $1.step) }
        for step in ordered {
            let marker = (step.step - step.step.rounded(.down)).isZero || plan.steps.contains(step) ? "" : " ✧"
            lines.append("| \(timeText(plan.date(of: step))) | \(step.step) | \(Rational.displayHoursMinutes(step.duration)) | \(step.instruction)\(marker) |")
        }
        let issues = plan.issues(existingWindows: [])
        lines.append("")
        if issues.isEmpty {
            lines.append("Hinweise: keine")
        } else {
            lines.append("Hinweise (\(issues.count)):")
            for issue in issues { lines.append("- \(issue.severity == .error ? "FEHLER" : "Hinweis"): \(issue.message)") }
        }
        if BakePlanAdvisor.hasNightSteps(plan, dayStart: 6, dayEnd: 23) {
            let suggestions = BakePlanAdvisor.nightFreeDates(for: plan, dayStart: 6, dayEnd: 23,
                                                             allowedDates: now...calendar.date(byAdding: .day, value: 14, to: finish)!)
            if suggestions.isEmpty {
                lines.append("Nachtfreie Alternative: keine innerhalb eines Tages")
            } else {
                for suggestion in suggestions {
                    lines.append("Nachtfreie Alternative: Fertig bis \(timeText(suggestion.date)) (Verschiebung \(suggestion.shift) min, Start \(timeText(suggestion.start)))")
                }
            }
        }
        if let window = plan.bakeWindow {
            let changes = window.temperatureChanges.map { "\(timeText($0.at)) → \($0.celsius) °C" }.joined(separator: ", ")
            lines.append("Ofenphase: \(timeText(window.start)) – \(timeText(window.end)), \(window.temperature.map { "\($0) °C" } ?? "ohne Temperatur")\(changes.isEmpty ? "" : ", Änderungen: \(changes)")")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Tests

    @Test("Every plan keeps its invariants, and the schedules are written out")
    func simulateTwentyRecipes() throws {
        var document = ["# Simulation der Backplanung – 20 Rezepte, „Fertig bis“ Samstag 21.11.2026 18:00, Tagesfenster 6–23 Uhr, Vorheizen 15/45 min", ""]
        for recipe in recipes {
            let planned = plan(recipe)
            let plan = planned.plan
            document.append(report(planned))

            // The bake is the step the recipe means.
            if let expected = recipe.expectedBake {
                #expect(plan.bakingStep?.instruction.hasPrefix(expected) == true,
                        "\(recipe.name): bake step is „\(plan.bakingStep?.instruction ?? "none")“")
            } else {
                #expect(plan.bakingStep == nil, "\(recipe.name): unexpected bake step „\(plan.bakingStep?.instruction ?? "")“")
            }
            // Preheating as expected: generated, the recipe's own, or none.
            if let expectedPreheat = recipe.expectedPreheat {
                #expect(plan.preheatDuration == expectedPreheat, "\(recipe.name): preheat \(plan.preheatDuration)")
            } else {
                #expect(plan.generatedOvenStep == nil, "\(recipe.name): generated an oven step although the recipe has one")
            }
            // Finish on the chosen date, no step after the end, no negative recipe step.
            #expect(plan.date(of: plan.endStep) == finish, "\(recipe.name): end not on the finish date")
            #expect(plan.steps.allSatisfy { $0.startTime >= 0 }, "\(recipe.name): a step before the start")
            #expect(plan.steps.allSatisfy { $0.startTime + $0.duration <= plan.totalMinutes }, "\(recipe.name): a step runs past the end")
            // Groups follow one another: a later main step never starts before an earlier one ends.
            let groups = Dictionary(grouping: plan.steps) { Int($0.step) }.sorted { $0.key < $1.key }
            for (earlier, later) in zip(groups, groups.dropFirst()) {
                let earlierEnd = earlier.value.map { $0.startTime + $0.duration }.max() ?? 0
                let laterStart = later.value.map(\.startTime).min() ?? 0
                #expect(laterStart >= earlierEnd, "\(recipe.name): step \(later.key) starts before step \(earlier.key) ends")
            }
            // The generated oven step ends exactly when the bake begins.
            if let oven = plan.generatedOvenStep, let bake = plan.bakingStep {
                #expect(oven.startTime + oven.duration == bake.startTime, "\(recipe.name): oven step does not meet the bake")
            }
            // A turn-down step falls inside the bake.
            if let turnDown = plan.generatedTurnDownStep, let bake = plan.bakingStep {
                #expect(turnDown.startTime >= bake.startTime && turnDown.startTime < bake.startTime + bake.duration,
                        "\(recipe.name): turn-down outside the bake")
            }
            // The generated steps say what the recipe says. The oven goes on at
            // the temperature the bake names.
            if let oven = plan.generatedOvenStep, let temperature = plan.ovenTemperature {
                #expect(oven.instruction.contains(temperature), "\(recipe.name): „\(oven.instruction)“ names no \(temperature)")
            }
            if let turnDown = plan.generatedTurnDownStep, let bake = plan.bakingStep {
                let folded = bake.instruction.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
                // The lower temperature is the bake's, stated or stored.
                let lower = turnDown.instruction.split(whereSeparator: { !$0.isNumber }).first.map(String.init) ?? ""
                #expect(bake.instruction.contains(lower) || bake.oven?.fallingTo.map(String.init) == lower,
                        "\(recipe.name): „\(turnDown.instruction)“ names a temperature the bake does not")
                // Steam is let out only where the bake has steam and no step of its own lets it out.
                let namesSteam = ["Dampf", "steam", "buée"].contains(where: turnDown.instruction.contains)
                let bakeHasSteam = ["dampf", "schwaden", "steam", "buee", "vapeur"].contains(where: folded.contains) || bake.oven?.steam == true
                let ownRelease = plan.steps.contains { $0.startTime > bake.startTime && BakePlan.isSteamReleaseInstruction($0.instruction) }
                if namesSteam {
                    #expect(bakeHasSteam && !ownRelease, "\(recipe.name): „\(turnDown.instruction)“ lets out steam the recipe does not have there")
                    // At the minute the bake lets it out, when it says.
                    if let release = BakePlan.steamReleaseMinutes(in: bake.instruction) {
                        #expect(turnDown.startTime == bake.startTime + release,
                                "\(recipe.name): steam let out at +\(turnDown.startTime - bake.startTime), the bake says +\(release)")
                    }
                }
            }
            // Where the bake says when the steam goes, a step lets it out then;
            // a step that lets it out "nach N Minuten" falls N minutes into the bake.
            if let bake = plan.bakingStep {
                let releases = plan.allSteps.filter { BakePlan.isSteamReleaseInstruction($0.instruction) }
                if let minutes = BakePlan.steamReleaseMinutes(in: bake.instruction), minutes < bake.duration {
                    #expect(releases.contains { $0.startTime == bake.startTime + minutes },
                            "\(recipe.name): no step lets the steam out at +\(minutes)")
                }
                for release in releases where release != bake
                    && !BakePlan.isGeneratedSteamReleaseInstruction(release.instruction)
                    && !BakePlan.isTurnDownInstruction(release.instruction) {
                    if let minutes = BakePlan.steamReleaseMinutes(in: release.instruction), minutes < bake.duration {
                        #expect(release.startTime == bake.startTime + minutes,
                                "\(recipe.name): „\(release.instruction)“ at +\(release.startTime - bake.startTime)")
                    }
                }
            }
            // A feeding ends as a feeding, a bread as a bake.
            #expect((plan.endStep.instruction.contains("Fütterung")) == recipe.isStarterFeeding || recipe.language != "de",
                    "\(recipe.name): end step „\(plan.endStep.instruction)“")

            // No two of the recipe's own steps that take time start in the same
            // minute. Generated steps may: the oven goes on while the dough is
            // spread, a cold oven with the bake, a turn-down right after loading.
            let starts = plan.steps.filter { $0.duration > 0 }.map(\.startTime)
            #expect(Set(starts).count == starts.count, "\(recipe.name): two steps at the same minute \(starts.sorted())")
            // The oven never goes on before the plan starts.
            if let oven = plan.generatedOvenStep {
                #expect(oven.startTime >= 0, "\(recipe.name): oven switched on before the start")
            }
        }
        let url = URL(fileURLWithPath: "/tmp/bakeplan-simulation.md")
        try document.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        print("Simulation report: \(url.path)")
    }
}
