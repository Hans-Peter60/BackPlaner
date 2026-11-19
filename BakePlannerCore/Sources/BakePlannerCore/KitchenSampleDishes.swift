//
//  KitchenSampleDishes.swift
//  BakePlannerCore
//
//  Three dishes from a 35-minute cooking show, broken into the steps a cook
//  actually does, with estimated hands-on and unattended minutes and how
//  long each result keeps. The recipes name hardly any work times, so the
//  minutes are estimates (docs/Idee-Gegen-die-Uhr.md keeps them as tables
//  for correction). The ovens are preheated before the clock starts, as in
//  the show, so no step heats one. The CookPlanner app shows these dishes
//  until it has an import of its own; the scheduler's tests use them too.
//

import Foundation

/// A dish as a set of work steps.
public struct KitchenDish: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let tasks: [KitchenTask]

    public init(id: String, name: String, tasks: [KitchenTask]) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }

    /// The parts of the dish, in the order their steps first appear.
    public var components: [String] {
        var seen = [String]()
        for task in tasks where !task.component.isEmpty && !seen.contains(task.component) {
            seen.append(task.component)
        }
        return seen
    }
}

public enum KitchenSampleDishes {

    /// The budget the show allows.
    public static let budget = 35

    public static let all: [KitchenDish] = [perlhuhnbrust, wirsingrolle, geschnetzeltes]

    /// Gebratene Perlhuhnbrust mit Bergkäse-Rahm-Wirsing, gebratenen
    /// Kräuterseitlingen und glasierter Verjus-Birne.
    public static let perlhuhnbrust = KitchenDish(
        id: "perlhuhnbrust",
        name: "Perlhuhnbrust mit Rahm-Wirsing, Kräuterseitlingen und Verjus-Birne",
        tasks: [
            KitchenTask(id: "a1", name: "Perlhuhn trocken tupfen, Sehnen entfernen, Haut salzen", component: "Perlhuhnbrust", hands: 2),
            KitchenTask(id: "a2", name: "Perlhuhn auf der Haut braten", component: "Perlhuhnbrust", hands: 1, unattended: 5, station: .burner, after: ["a1"], maxWait: 0),
            KitchenTask(id: "a3", name: "Wenden, Butter, Knoblauch, Thymian, arrosieren", component: "Perlhuhnbrust", hands: 3, station: .burner, after: ["a2"], maxWait: 0),
            KitchenTask(id: "a4", name: "Perlhuhn ruhen lassen", component: "Perlhuhnbrust", hands: 0, unattended: 5, after: ["a3"], maxWait: 3),
            KitchenTask(id: "a5", name: "Perlhuhn würzen und tranchieren", component: "Perlhuhnbrust", hands: 2, after: ["a4"], maxWait: 3),

            KitchenTask(id: "w1", name: "Wirsing in Streifen, Schalotte und Knoblauch würfeln", component: "Wirsing", hands: 5),
            KitchenTask(id: "w2", name: "Anschwitzen, Wirsing zugeben, Fond und Sahne angießen", component: "Wirsing", hands: 4, station: .burner, after: ["w1"]),
            KitchenTask(id: "w3", name: "Wirsing cremig garen", component: "Wirsing", hands: 0, unattended: 7, station: .burner, after: ["w2"]),
            KitchenTask(id: "w4", name: "Bergkäse reiben", component: "Wirsing", hands: 2),
            KitchenTask(id: "w5", name: "Miso anrühren, Käse unterziehen, abschmecken", component: "Wirsing", hands: 2, station: .burner, after: ["w3", "w4"]),

            KitchenTask(id: "p1", name: "Kräuterseitlinge in Scheiben schneiden", component: "Kräuterseitlinge", hands: 3),
            KitchenTask(id: "p2", name: "Pilze ohne Bewegung goldbraun braten", component: "Kräuterseitlinge", hands: 1, unattended: 3, station: .burner, after: ["p1"], maxWait: 0),
            KitchenTask(id: "p3", name: "Wenden, zweite Seite, Butter, Knoblauch, Thymian, würzen", component: "Kräuterseitlinge", hands: 3, station: .burner, after: ["p2"]),

            KitchenTask(id: "b1", name: "Birne vierteln, entkernen, schneiden", component: "Verjus-Birne", hands: 2),
            KitchenTask(id: "b2", name: "Birne anbraten, Honig, Verjus, glasieren", component: "Verjus-Birne", hands: 5, station: .burner, after: ["b1"], maxWait: 10),

            KitchenTask(id: "g1", name: "Orange reiben, Kräuter zupfen, Käse reiben", component: "Garnitur", hands: 2),

            KitchenTask(id: "s1", name: "Anrichten", component: "Anrichten", hands: 3, after: ["a5", "w5", "p3", "b2", "g1"])
        ])

    /// Mit Perlhuhnbrust, Kräuterseitlingen, Perlgraupen und Bergkäse
    /// gefüllte Wirsingrolle mit Sahnesauce, Birnen-Haselnuss-Kompott und
    /// Estragon-Öl.
    public static let wirsingrolle = KitchenDish(
        id: "wirsingrolle",
        name: "Gefüllte Wirsingrolle mit Sahnesauce, Birnen-Haselnuss-Kompott und Estragon-Öl",
        tasks: [
            KitchenTask(id: "r1", name: "Perlgraupen waschen, mit Lorbeer in Salzwasser kochen", component: "Wirsingrolle", hands: 2, unattended: 25, station: .burner),
            KitchenTask(id: "r2", name: "Wirsingblätter von den Adern befreien", component: "Wirsingrolle", hands: 3),
            KitchenTask(id: "r3", name: "Wirsingblätter in Salzwasser garen", component: "Wirsingrolle", hands: 1, unattended: 8, station: .burner, after: ["r2"]),
            KitchenTask(id: "r4", name: "Blätter abtropfen lassen", component: "Wirsingrolle", hands: 1, after: ["r3"]),
            KitchenTask(id: "r5", name: "Haut abziehen, Fleisch vom Knochen lösen, würfeln", component: "Wirsingrolle", hands: 3),
            KitchenTask(id: "r6", name: "Haut langsam ausbraten", component: "Wirsingrolle", hands: 1, unattended: 8, station: .burner, after: ["r5"]),
            KitchenTask(id: "r7", name: "Fleisch in Öl anbraten", component: "Wirsingrolle", hands: 3, station: .burner, after: ["r5"]),
            KitchenTask(id: "r8", name: "Kräuterseitlinge klein schneiden, anbraten, würzen", component: "Wirsingrolle", hands: 4, station: .burner),
            KitchenTask(id: "r9", name: "Käse fein würfeln", component: "Wirsingrolle", hands: 1),
            KitchenTask(id: "r10", name: "Graupen abgießen, Füllung mischen, mit Verjus abschmecken", component: "Wirsingrolle", hands: 3, after: ["r1", "r7", "r8", "r9"]),
            KitchenTask(id: "r11", name: "Blätter füllen, rollen, rundherum anbraten", component: "Wirsingrolle", hands: 5, station: .burner, after: ["r10", "r4"]),

            KitchenTask(id: "k1", name: "Birne schälen, entkernen, würfeln", component: "Kompott", hands: 2),
            KitchenTask(id: "k2", name: "Birne in Butter dünsten, abschmecken", component: "Kompott", hands: 2, unattended: 5, station: .burner, after: ["k1"]),
            KitchenTask(id: "n1", name: "Haselnüsse im Ofen rösten", component: "Kompott", hands: 1, unattended: 8, station: .oven),
            KitchenTask(id: "n2", name: "Nüsse hacken und unterheben", component: "Kompott", hands: 1, after: ["n1", "k2"]),

            KitchenTask(id: "s1", name: "Sahne und Fond reduzieren", component: "Sahnesauce", hands: 1, unattended: 8, station: .burner),
            KitchenTask(id: "s2", name: "Sauce mit Verjus und Miso abschmecken", component: "Sahnesauce", hands: 1, after: ["s1"]),

            KitchenTask(id: "e1", name: "Öl auf 60 °C erhitzen", component: "Estragon-Öl", hands: 1, unattended: 3, station: .burner),
            KitchenTask(id: "e2", name: "Estragon pürieren, passieren, salzen", component: "Estragon-Öl", hands: 3, after: ["e1"]),

            KitchenTask(id: "x1", name: "Anrichten", component: "Anrichten", hands: 3, after: ["r11", "n2", "s2", "e2"])
        ])

    /// Geschnetzeltes von der Perlhuhnbrust in Verjus-Estragon-Rahm mit
    /// gebratenen Kräuterseitlingen, karamellisierter Birne und knuspriger
    /// Hühnerhaut.
    public static let geschnetzeltes = KitchenDish(
        id: "geschnetzeltes",
        name: "Perlhuhn-Geschnetzeltes in Verjus-Estragon-Rahm mit Pilzen, Birne und knuspriger Haut",
        tasks: [
            KitchenTask(id: "m1", name: "Haut lösen, Fleisch in Streifen, Schalotte würfeln, Estragon schneiden", component: "Geschnetzeltes", hands: 6),
            KitchenTask(id: "m2", name: "Fleisch 60 Sekunden scharf anbraten, herausnehmen, würzen", component: "Geschnetzeltes", hands: 2, station: .burner, after: ["m1"], maxWait: 1),
            KitchenTask(id: "m3", name: "Schalotte, ablöschen, einkochen, Fond reduzieren, Sahne sämig", component: "Geschnetzeltes", hands: 4, unattended: 4, station: .burner, after: ["m2"], maxWait: 10),
            KitchenTask(id: "m4", name: "Kalte Butter, Estragon, Fleisch warmziehen", component: "Geschnetzeltes", hands: 2, station: .burner, after: ["m3"], maxWait: 3),

            KitchenTask(id: "h1", name: "Haut zwischen Backpapier, beschweren, in den Ofen", component: "Knusprige Haut", hands: 2, after: ["m1"]),
            KitchenTask(id: "h2", name: "Haut goldbraun backen", component: "Knusprige Haut", hands: 0, unattended: 20, station: .oven, after: ["h1"]),
            KitchenTask(id: "h3", name: "Haut salzen", component: "Knusprige Haut", hands: 1, after: ["h2"]),

            KitchenTask(id: "p1", name: "Kräuterseitlinge in Scheiben, Schalotte würfeln", component: "Kräuterseitlinge", hands: 4),
            KitchenTask(id: "p2", name: "Pilze 2 Minuten anbraten, wenden, salzen, Thymian", component: "Kräuterseitlinge", hands: 4, station: .burner, after: ["p1"]),

            KitchenTask(id: "b1", name: "Birne in Spalten schneiden, entkernen", component: "Birne", hands: 2),
            KitchenTask(id: "b2", name: "Birne 2 Minuten pro Seite karamellisieren", component: "Birne", hands: 5, station: .burner, after: ["b1"], maxWait: 10),

            KitchenTask(id: "g1", name: "Haselnüsse grob hacken", component: "Garnitur", hands: 2),

            KitchenTask(id: "x1", name: "Anrichten", component: "Anrichten", hands: 3, after: ["m4", "h3", "p2", "b2", "g1"])
        ])
}
