//
//  KitchenSampleDishes.swift
//  BakePlannerCore
//
//  Three dishes from a 35-minute cooking show, broken into the steps a cook
//  actually does, with estimated hands-on and unattended minutes and how
//  long each result keeps. The recipes name hardly any work times, so the
//  minutes are estimates (docs/cookplanner/Idee-Gegen-die-Uhr.md keeps them as tables
//  for correction). The ovens are preheated before the clock starts, as in
//  the show, so no step heats one. The CookPlanner app shows these dishes
//  until it has an import of its own; the scheduler's tests use them too.
//

import Foundation

public enum KitchenSampleDishes {

    /// The budget the show allows.
    public static let budget = 35

    public static let all: [KitchenDish] = [perlhuhnbrust, wirsingrolle, geschnetzeltes]

    /// Gebratene Perlhuhnbrust mit Bergkäse-Rahm-Wirsing, gebratenen
    /// Kräuterseitlingen und glasierter Verjus-Birne.
    public static let perlhuhnbrust = KitchenDish(
        id: "perlhuhnbrust",
        name: "Perlhuhnbrust mit Rahm-Wirsing, Kräuterseitlingen und Verjus-Birne",
        source: .sample,
        tasks: [
            KitchenTask(id: "a1", name: "Perlhuhn trocken tupfen, Sehnen entfernen, Haut salzen", component: "Perlhuhnbrust", hands: 2, ingredientIDs: ["a-huhn", "a-salz1"]),
            KitchenTask(id: "a2", name: "Perlhuhn auf der Haut braten", component: "Perlhuhnbrust", hands: 1, unattended: 5, station: .burner, after: ["a1"], maxWait: 0, window: 5...6, ingredientIDs: ["a-oel1"]),
            KitchenTask(id: "a3", name: "Wenden, Butter, Knoblauch, Thymian, arrosieren", component: "Perlhuhnbrust", hands: 3, station: .burner, after: ["a2"], maxWait: 0, ingredientIDs: ["a-butter1", "a-knob1", "a-thymian1"]),
            KitchenTask(id: "a4", name: "Perlhuhn ruhen lassen", component: "Perlhuhnbrust", hands: 0, unattended: 5, after: ["a3"], maxWait: 3),
            KitchenTask(id: "a5", name: "Perlhuhn würzen und tranchieren", component: "Perlhuhnbrust", hands: 2, after: ["a4"], maxWait: 3, ingredientIDs: ["a-salz1", "a-pfeffer1"]),

            KitchenTask(id: "w1", name: "Wirsing in Streifen, Schalotte und Knoblauch würfeln", component: "Wirsing", hands: 5, ingredientIDs: ["a-wirsing", "a-schalotte", "a-knob2"]),
            KitchenTask(id: "w2", name: "Anschwitzen, Wirsing zugeben, Fond und Sahne angießen", component: "Wirsing", hands: 4, station: .burner, after: ["w1"], ingredientIDs: ["a-butter2", "a-fond", "a-sahne"]),
            KitchenTask(id: "w3", name: "Wirsing cremig garen", component: "Wirsing", hands: 0, unattended: 7, station: .burner, after: ["w2"], window: 6...8),
            KitchenTask(id: "w4", name: "Bergkäse reiben", component: "Wirsing", hands: 2, ingredientIDs: ["a-kaese1"]),
            KitchenTask(id: "w5", name: "Miso anrühren, Käse unterziehen, abschmecken", component: "Wirsing", hands: 2, station: .burner, after: ["w3", "w4"], ingredientIDs: ["a-miso", "a-muskat", "a-salz2", "a-pfeffer2"]),

            KitchenTask(id: "p1", name: "Kräuterseitlinge in Scheiben schneiden", component: "Kräuterseitlinge", hands: 3, ingredientIDs: ["a-pilze"]),
            KitchenTask(id: "p2", name: "Pilze ohne Bewegung goldbraun braten", component: "Kräuterseitlinge", hands: 1, unattended: 3, station: .burner, after: ["p1"], maxWait: 0, ingredientIDs: ["a-oel2"]),
            KitchenTask(id: "p3", name: "Wenden, zweite Seite, Butter, Knoblauch, Thymian, würzen", component: "Kräuterseitlinge", hands: 3, station: .burner, after: ["p2"], ingredientIDs: ["a-butter3", "a-knob3", "a-thymian2", "a-salz3", "a-pfeffer3"]),

            KitchenTask(id: "b1", name: "Birne vierteln, entkernen, schneiden", component: "Verjus-Birne", hands: 2, ingredientIDs: ["a-birne"]),
            KitchenTask(id: "b2", name: "Birne anbraten, Honig, Verjus, glasieren", component: "Verjus-Birne", hands: 5, station: .burner, after: ["b1"], maxWait: 10, ingredientIDs: ["a-butter4", "a-honig", "a-verjus", "a-thymian3", "a-salz4"]),

            KitchenTask(id: "g1", name: "Orange reiben, Kräuter zupfen, Käse reiben", component: "Garnitur", hands: 2, ingredientIDs: ["a-orange", "a-kaese2", "a-petersilie", "a-thymian4"]),

            KitchenTask(id: "s1", name: "Anrichten", component: "Anrichten", hands: 3, after: ["a5", "w5", "p3", "b2", "g1"], ingredientIDs: ["a-pfeffer4"])
        ], ingredients: [
            KitchenIngredient(id: "a-huhn", name: "Perlhuhnbrüste", amount: 2, unit: "Stück", component: "Perlhuhnbrust", note: "mit Haut und Flügelknochen"),
            KitchenIngredient(id: "a-knob1", name: "Knoblauchzehe", amount: 1, component: "Perlhuhnbrust"),
            KitchenIngredient(id: "a-butter1", name: "Butter", amount: 30, unit: "g", component: "Perlhuhnbrust"),
            KitchenIngredient(id: "a-oel1", name: "Neutrales Öl", amount: 1, unit: "EL", component: "Perlhuhnbrust"),
            KitchenIngredient(id: "a-thymian1", name: "Thymian", amount: 2, unit: "Zweige", component: "Perlhuhnbrust"),
            KitchenIngredient(id: "a-salz1", name: "Salz", component: "Perlhuhnbrust"),
            KitchenIngredient(id: "a-pfeffer1", name: "Schwarzer Pfeffer", component: "Perlhuhnbrust"),
            KitchenIngredient(id: "a-wirsing", name: "Wirsing", amount: 300, unit: "g", component: "Wirsing"),
            KitchenIngredient(id: "a-schalotte", name: "Schalotte", amount: 1, component: "Wirsing", note: "klein"),
            KitchenIngredient(id: "a-knob2", name: "Knoblauchzehe", amount: 1, component: "Wirsing"),
            KitchenIngredient(id: "a-kaese1", name: "Bergkäse", amount: 60, unit: "g", component: "Wirsing", note: "kräftig gereift"),
            KitchenIngredient(id: "a-butter2", name: "Butter", amount: 20, unit: "g", component: "Wirsing"),
            KitchenIngredient(id: "a-sahne", name: "Sahne", amount: 100, unit: "ml", component: "Wirsing"),
            KitchenIngredient(id: "a-fond", name: "Gemüsefond", amount: 50, unit: "ml", component: "Wirsing"),
            KitchenIngredient(id: "a-miso", name: "Helle Miso-Paste", amount: 0.5, unit: "TL", component: "Wirsing"),
            KitchenIngredient(id: "a-muskat", name: "Muskatnuss", component: "Wirsing"),
            KitchenIngredient(id: "a-salz2", name: "Salz", component: "Wirsing"),
            KitchenIngredient(id: "a-pfeffer2", name: "Schwarzer Pfeffer", component: "Wirsing"),
            KitchenIngredient(id: "a-pilze", name: "Kräuterseitlinge", amount: 200, unit: "g", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "a-knob3", name: "Knoblauchzehe", amount: 1, component: "Kräuterseitlinge"),
            KitchenIngredient(id: "a-butter3", name: "Butter", amount: 20, unit: "g", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "a-oel2", name: "Neutrales Öl", amount: 1, unit: "EL", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "a-thymian2", name: "Thymian", amount: 2, unit: "Zweige", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "a-salz3", name: "Salz", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "a-pfeffer3", name: "Schwarzer Pfeffer", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "a-birne", name: "Birne", amount: 1, component: "Verjus-Birne"),
            KitchenIngredient(id: "a-butter4", name: "Butter", amount: 15, unit: "g", component: "Verjus-Birne"),
            KitchenIngredient(id: "a-honig", name: "Honig", amount: 1, unit: "TL", component: "Verjus-Birne"),
            KitchenIngredient(id: "a-verjus", name: "Verjus", amount: 60, unit: "ml", component: "Verjus-Birne"),
            KitchenIngredient(id: "a-thymian3", name: "Thymian", amount: 1, unit: "Zweig", component: "Verjus-Birne"),
            KitchenIngredient(id: "a-salz4", name: "Salz", component: "Verjus-Birne"),
            KitchenIngredient(id: "a-orange", name: "Orange", amount: 1, component: "Garnitur", note: "Abrieb"),
            KitchenIngredient(id: "a-kaese2", name: "Bergkäse", amount: 20, unit: "g", component: "Garnitur", note: "kräftig gereift"),
            KitchenIngredient(id: "a-petersilie", name: "Petersilie", amount: 1, unit: "Zweig", component: "Garnitur"),
            KitchenIngredient(id: "a-thymian4", name: "Thymian", amount: 1, unit: "Zweig", component: "Garnitur"),
            KitchenIngredient(id: "a-pfeffer4", name: "Schwarzer Pfeffer", component: "Garnitur")
        ])

    /// Mit Perlhuhnbrust, Kräuterseitlingen, Perlgraupen und Bergkäse
    /// gefüllte Wirsingrolle mit Sahnesauce, Birnen-Haselnuss-Kompott und
    /// Estragon-Öl.
    public static let wirsingrolle = KitchenDish(
        id: "wirsingrolle",
        name: "Gefüllte Wirsingrolle mit Sahnesauce, Birnen-Haselnuss-Kompott und Estragon-Öl",
        source: .sample,
        tasks: [
            KitchenTask(id: "r1", name: "Perlgraupen waschen, mit Lorbeer in Salzwasser kochen", component: "Wirsingrolle", hands: 2, unattended: 25, station: .burner, ingredientIDs: ["b-graupen", "b-lorbeer", "b-salz1"]),
            KitchenTask(id: "r2", name: "Wirsingblätter von den Adern befreien", component: "Wirsingrolle", hands: 3, ingredientIDs: ["b-wirsing"]),
            KitchenTask(id: "r3", name: "Wirsingblätter in Salzwasser garen", component: "Wirsingrolle", hands: 1, unattended: 8, station: .burner, after: ["r2"], ingredientIDs: ["b-salz1"]),
            KitchenTask(id: "r4", name: "Blätter abtropfen lassen", component: "Wirsingrolle", hands: 1, after: ["r3"]),
            KitchenTask(id: "r5", name: "Haut abziehen, Fleisch vom Knochen lösen, würfeln", component: "Wirsingrolle", hands: 3, ingredientIDs: ["b-huhn"]),
            KitchenTask(id: "r6", name: "Haut langsam ausbraten", component: "Wirsingrolle", hands: 1, unattended: 8, station: .burner, after: ["r5"]),
            KitchenTask(id: "r7", name: "Fleisch in Öl anbraten", component: "Wirsingrolle", hands: 3, station: .burner, after: ["r5"], ingredientIDs: ["b-oel1"]),
            KitchenTask(id: "r8", name: "Kräuterseitlinge klein schneiden, anbraten, würzen", component: "Wirsingrolle", hands: 4, station: .burner, ingredientIDs: ["b-pilze", "b-salz1", "b-pfeffer"]),
            KitchenTask(id: "r9", name: "Käse fein würfeln", component: "Wirsingrolle", hands: 1, ingredientIDs: ["b-kaese"]),
            KitchenTask(id: "r10", name: "Graupen abgießen, Füllung mischen, mit Verjus abschmecken", component: "Wirsingrolle", hands: 3, after: ["r1", "r7", "r8", "r9"], ingredientIDs: ["b-verjus1"]),
            KitchenTask(id: "r11", name: "Blätter füllen, rollen, rundherum anbraten", component: "Wirsingrolle", hands: 5, station: .burner, after: ["r10", "r4"]),

            KitchenTask(id: "k1", name: "Birne schälen, entkernen, würfeln", component: "Kompott", hands: 2, ingredientIDs: ["b-birne"]),
            KitchenTask(id: "k2", name: "Birne in Butter dünsten, abschmecken", component: "Kompott", hands: 2, unattended: 5, station: .burner, after: ["k1"], ingredientIDs: ["b-butter", "b-salz2", "b-verjus2"]),
            KitchenTask(id: "n1", name: "Haselnüsse im Ofen rösten", component: "Kompott", hands: 1, unattended: 8, station: .oven, ovenTemperature: 160, ingredientIDs: ["b-nuesse"]),
            KitchenTask(id: "n2", name: "Nüsse hacken und unterheben", component: "Kompott", hands: 1, after: ["n1", "k2"]),

            KitchenTask(id: "s1", name: "Sahne und Fond reduzieren", component: "Sahnesauce", hands: 1, unattended: 8, station: .burner, ingredientIDs: ["b-sahne", "b-fond"]),
            KitchenTask(id: "s2", name: "Sauce mit Verjus und Miso abschmecken", component: "Sahnesauce", hands: 1, after: ["s1"], ingredientIDs: ["b-verjus3", "b-miso"]),

            KitchenTask(id: "e1", name: "Öl auf 60 °C erhitzen", component: "Estragon-Öl", hands: 1, unattended: 3, station: .burner, ingredientIDs: ["b-rapsoel"]),
            KitchenTask(id: "e2", name: "Estragon pürieren, passieren, salzen", component: "Estragon-Öl", hands: 3, after: ["e1"], ingredientIDs: ["b-estragon", "b-salz3"]),

            KitchenTask(id: "x1", name: "Anrichten", component: "Anrichten", hands: 3, after: ["r11", "n2", "s2", "e2"])
        ], ingredients: [
            KitchenIngredient(id: "b-huhn", name: "Perlhuhnbrust", amount: 0.5, component: "Wirsingrolle", note: "mit Haut und Flügelknochen"),
            KitchenIngredient(id: "b-wirsing", name: "Wirsing", amount: 1, component: "Wirsingrolle"),
            KitchenIngredient(id: "b-pilze", name: "Kräuterseitlinge", amount: 2, component: "Wirsingrolle"),
            KitchenIngredient(id: "b-graupen", name: "Perlgraupen", amount: 50, unit: "g", component: "Wirsingrolle"),
            KitchenIngredient(id: "b-kaese", name: "Bergkäse", amount: 20, unit: "g", component: "Wirsingrolle", note: "kräftig gereift"),
            KitchenIngredient(id: "b-verjus1", name: "Verjus", amount: 1, unit: "EL", component: "Wirsingrolle"),
            KitchenIngredient(id: "b-lorbeer", name: "Lorbeerblatt", amount: 1, component: "Wirsingrolle"),
            KitchenIngredient(id: "b-salz1", name: "Salz", component: "Wirsingrolle"),
            KitchenIngredient(id: "b-pfeffer", name: "Schwarzer Pfeffer", component: "Wirsingrolle"),
            KitchenIngredient(id: "b-oel1", name: "Öl", component: "Wirsingrolle", note: "zum Braten"),
            KitchenIngredient(id: "b-birne", name: "Birne", amount: 1, component: "Kompott"),
            KitchenIngredient(id: "b-butter", name: "Butter", amount: 1, unit: "EL", component: "Kompott"),
            KitchenIngredient(id: "b-verjus2", name: "Verjus", amount: 1, unit: "EL", component: "Kompott"),
            KitchenIngredient(id: "b-nuesse", name: "Haselnüsse", amount: 2, unit: "EL", component: "Kompott"),
            KitchenIngredient(id: "b-salz2", name: "Salz", component: "Kompott"),
            KitchenIngredient(id: "b-sahne", name: "Sahne", amount: 100, unit: "ml", component: "Sahnesauce"),
            KitchenIngredient(id: "b-fond", name: "Geflügelfond", amount: 100, unit: "ml", component: "Sahnesauce"),
            KitchenIngredient(id: "b-verjus3", name: "Verjus", amount: 20, unit: "ml", component: "Sahnesauce"),
            KitchenIngredient(id: "b-miso", name: "Helle Miso-Paste", amount: 1, unit: "EL", component: "Sahnesauce"),
            KitchenIngredient(id: "b-estragon", name: "Estragon", amount: 1, unit: "Bund", component: "Estragon-Öl"),
            KitchenIngredient(id: "b-rapsoel", name: "Rapsöl", amount: 100, unit: "ml", component: "Estragon-Öl"),
            KitchenIngredient(id: "b-salz3", name: "Salz", component: "Estragon-Öl")
        ])

    /// Geschnetzeltes von der Perlhuhnbrust in Verjus-Estragon-Rahm mit
    /// gebratenen Kräuterseitlingen, karamellisierter Birne und knuspriger
    /// Hühnerhaut.
    public static let geschnetzeltes = KitchenDish(
        id: "geschnetzeltes",
        name: "Perlhuhn-Geschnetzeltes in Verjus-Estragon-Rahm mit Pilzen, Birne und knuspriger Haut",
        source: .sample,
        tasks: [
            KitchenTask(id: "m1", name: "Haut lösen, Fleisch in Streifen, Schalotte würfeln, Estragon schneiden", component: "Geschnetzeltes", hands: 6, ingredientIDs: ["c-huhn", "c-schalotte1", "c-estragon"]),
            KitchenTask(id: "m2", name: "Fleisch 60 Sekunden scharf anbraten, herausnehmen, würzen", component: "Geschnetzeltes", hands: 2, station: .burner, after: ["m1"], maxWait: 1, ingredientIDs: ["c-oel1", "c-salz1", "c-pfeffer"]),
            KitchenTask(id: "m3", name: "Schalotte, ablöschen, einkochen, Fond reduzieren, Sahne sämig", component: "Geschnetzeltes", hands: 4, unattended: 4, station: .burner, after: ["m2"], maxWait: 10, ingredientIDs: ["c-butter1", "c-verjus", "c-wein", "c-fond", "c-sahne"]),
            KitchenTask(id: "m4", name: "Kalte Butter, Estragon, Fleisch warmziehen", component: "Geschnetzeltes", hands: 2, station: .burner, after: ["m3"], maxWait: 3, ingredientIDs: ["c-butter2"]),

            KitchenTask(id: "h1", name: "Haut zwischen Backpapier, beschweren, in den Ofen", component: "Knusprige Haut", hands: 2, after: ["m1"], ingredientIDs: ["c-haut"]),
            KitchenTask(id: "h2", name: "Haut goldbraun backen", component: "Knusprige Haut", hands: 0, unattended: 20, station: .oven, after: ["h1"], window: 20...25, ovenTemperature: 160),
            KitchenTask(id: "h3", name: "Haut salzen", component: "Knusprige Haut", hands: 1, after: ["h2"], ingredientIDs: ["c-salz3"]),

            KitchenTask(id: "p1", name: "Kräuterseitlinge in Scheiben, Schalotte würfeln", component: "Kräuterseitlinge", hands: 4, ingredientIDs: ["c-pilze", "c-schalotte2"]),
            KitchenTask(id: "p2", name: "Pilze 2 Minuten anbraten, wenden, salzen, Thymian", component: "Kräuterseitlinge", hands: 4, station: .burner, after: ["p1"], ingredientIDs: ["c-oel2", "c-salz2", "c-thymian"]),

            KitchenTask(id: "b1", name: "Birne in Spalten schneiden, entkernen", component: "Birne", hands: 2, ingredientIDs: ["c-birne"]),
            KitchenTask(id: "b2", name: "Birne 2 Minuten pro Seite karamellisieren", component: "Birne", hands: 5, station: .burner, after: ["b1"], maxWait: 10, ingredientIDs: ["c-butter3", "c-zucker"]),

            KitchenTask(id: "g1", name: "Haselnüsse grob hacken", component: "Garnitur", hands: 2, ingredientIDs: ["c-nuesse"]),

            KitchenTask(id: "x1", name: "Anrichten", component: "Anrichten", hands: 3, after: ["m4", "h3", "p2", "b2", "g1"])
        ], ingredients: [
            KitchenIngredient(id: "c-huhn", name: "Perlhuhnbrüste", amount: 2, unit: "Stück", component: "Geschnetzeltes", note: "mit Haut und Flügelknochen"),
            KitchenIngredient(id: "c-schalotte1", name: "Schalotte", amount: 1, component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-sahne", name: "Sahne", amount: 250, unit: "ml", component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-butter1", name: "Butter", amount: 1.5, unit: "EL", component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-butter2", name: "Butter", amount: 20, unit: "g", component: "Geschnetzeltes", note: "kalt"),
            KitchenIngredient(id: "c-verjus", name: "Verjus", amount: 75, unit: "ml", component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-wein", name: "Weißwein", amount: 50, unit: "ml", component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-fond", name: "Geflügelfond", amount: 100, unit: "ml", component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-oel1", name: "Neutrales Öl", component: "Geschnetzeltes", note: "zum Braten"),
            KitchenIngredient(id: "c-estragon", name: "Estragon", amount: 1, unit: "Zweig", component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-salz1", name: "Salz", component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-pfeffer", name: "Schwarzer Pfeffer", component: "Geschnetzeltes"),
            KitchenIngredient(id: "c-pilze", name: "Kräuterseitlinge", amount: 300, unit: "g", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "c-schalotte2", name: "Schalotte", amount: 1, component: "Kräuterseitlinge"),
            KitchenIngredient(id: "c-oel2", name: "Neutrales Öl", component: "Kräuterseitlinge", note: "zum Braten"),
            KitchenIngredient(id: "c-thymian", name: "Thymian", amount: 4, unit: "Zweige", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "c-salz2", name: "Salz", component: "Kräuterseitlinge"),
            KitchenIngredient(id: "c-haut", name: "Haut der Perlhuhnbrüste", component: "Knusprige Haut"),
            KitchenIngredient(id: "c-salz3", name: "Salz", component: "Knusprige Haut"),
            KitchenIngredient(id: "c-birne", name: "Birne", amount: 1, component: "Birne"),
            KitchenIngredient(id: "c-butter3", name: "Butter", amount: 10, unit: "g", component: "Birne"),
            KitchenIngredient(id: "c-zucker", name: "Zucker", amount: 0.5, unit: "EL", component: "Birne"),
            KitchenIngredient(id: "c-nuesse", name: "Haselnüsse", amount: 50, unit: "g", component: "Garnitur")
        ])
}
