import BakePlannerCore
import Foundation
import SwiftUI

/// The three free-standing calculators of the iPhone's main menu, opened
/// from the recipe list's "Mehr" menu: the water temperature for a target
/// dough temperature, swapping a flour, and exchanging a starter for one of
/// another TA. The arithmetic and the hints come from BakePlannerCore; the
/// wording is the iPhone's.
enum Calculator: Int {
    case doughTemperature
    case flourSubstitution
    case starterYield
}

struct CalculatorSheet: View {
    let calculator: Calculator
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Group {
            switch calculator {
            case .doughTemperature: DoughTemperatureView()
            case .flourSubstitution: FlourSubstitutionCalculator()
            case .starterYield: StarterYieldCalculator()
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
    }
}

/// The big figure every calculator leads with, and a line under it.
struct CalculatorResult<Detail: View>: View {
    let title: LocalizedStringKey
    let value: String
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.largeTitle)
                .bold()
            detail
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// A row with a label and a value, as the iPhone's LabeledContent in a
/// Stepper.
struct ValueLabel: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value)
                .foregroundStyle(.secondary)
        }
    }
}

/// "+20 g", "−20 g", "±0 g" — a true minus sign, not a hyphen.
func gramsDeltaText(_ grams: Double) -> String {
    let whole = Int(grams.rounded())
    if whole == 0 { return "±0 g" }
    return whole > 0 ? "+\(whole) g" : "−\(-whole) g"
}

// MARK: - Dough temperature

/// Works out the water temperature a dough needs to hit a target dough
/// temperature (DoughTemperatureCalculator). The friction factor is kept
/// as a setting under the iPhone's key.
struct DoughTemperatureView: View {
    @State var targetDoughTemperature = 24
    @State var roomTemperature = 21
    @State var flourAtRoomTemperature = true
    @State var flourTemperature = 21
    @State var usesPreferment = false
    @State var prefermentTemperature = 21
    @State var frictionFactor = AppSettings.storedFrictionFactor

    private var waterTemperature: Int {
        DoughTemperatureCalculator.waterTemperature(
            targetDoughTemperature: targetDoughTemperature,
            roomTemperature: roomTemperature,
            flourTemperature: flourAtRoomTemperature ? roomTemperature : flourTemperature,
            frictionFactor: frictionFactor,
            prefermentTemperature: usesPreferment ? prefermentTemperature : nil
        )
    }

    var body: some View {
        Form {
            Section {
                CalculatorResult(title: "Schüttwassertemperatur", value: "\(waterTemperature) °C") {
                    switch DoughTemperatureCalculator.feasibility(ofWaterTemperature: waterTemperature) {
                    case .ok:
                        EmptyView()
                    case .tooCold:
                        Label("Kälter als Eiswasser – mit diesen Werten kaum erreichbar.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                    case .tooHot:
                        Label("Sehr heißes Wasser nötig – prüfe Ziel- und Reibungswärme.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.orange)
                    }
                }
            }

            Section {
                Stepper(value: $targetDoughTemperature, in: 15...32) {
                    ValueLabel(title: "Teig", value: "\(targetDoughTemperature) °C")
                }
            } header: {
                Text("Zieltemperatur")
            }

            Section {
                Stepper(value: $roomTemperature, in: 0...35) {
                    ValueLabel(title: "Raum", value: "\(roomTemperature) °C")
                }
                Toggle("Mehl hat Raumtemperatur", isOn: $flourAtRoomTemperature)
                if !flourAtRoomTemperature {
                    Stepper(value: $flourTemperature, in: -10...35) {
                        ValueLabel(title: "Mehl", value: "\(flourTemperature) °C")
                    }
                }
                Toggle("Mit Sauerteig oder Vorteig", isOn: $usesPreferment)
                if usesPreferment {
                    Stepper(value: $prefermentTemperature, in: 0...35) {
                        ValueLabel(title: "Sauerteig/Vorteig", value: "\(prefermentTemperature) °C")
                    }
                }
            } header: {
                Text("Zutaten")
            }

            Section {
                Stepper(value: $frictionFactor,
                        in: AppSettings.minimumFrictionFactor...AppSettings.maximumFrictionFactor) {
                    ValueLabel(title: "Reibungswärme", value: "\(frictionFactor) °C")
                }
            } footer: {
                Text("Die Wärme, die der Teig zusätzlich beim Kneten aufnimmt. Vergleiche nach dem Kneten die gemessene Teigtemperatur mit der Zieltemperatur und passe den Wert entsprechend an – einmal kalibriert, gilt er für jedes Rezept.")
            }
        }
        .navigationTitle("Teigtemperatur")
        .onChange(of: frictionFactor) { _, value in
            SettingsFile.set(value, forKey: AppSettingsKeys.doughFrictionFactor)
        }
    }
}

// MARK: - Flour substitution

/// A flour from the catalogue, chosen in two steps — grain, then the flour
/// of that grain — because Skip's Picker has no sections.
struct FlourChoice: View {
    let title: LocalizedStringKey
    @Binding var flourID: String

    private var flour: FlourSubstitution.Flour {
        FlourSubstitution.catalog.first { $0.id == flourID } ?? FlourSubstitution.wheat550
    }

    var body: some View {
        Text(title)
            .font(.headline)
        Picker("Getreide", selection: Binding(
            get: { flour.grain.rawValue },
            set: { raw in
                if let grain = FlourSubstitution.Grain(rawValue: raw),
                   let first = FlourSubstitution.flours(of: grain).first {
                    flourID = first.id
                }
            })) {
            ForEach(FlourSubstitution.Grain.allCases) { grain in
                Text(verbatim: grain.title).tag(grain.rawValue)
            }
        }
        Picker("Mehl", selection: $flourID) {
            ForEach(FlourSubstitution.flours(of: flour.grain)) { flour in
                Text(verbatim: flour.title).tag(flour.id)
            }
        }
    }
}

/// Swapping one flour for another: the water changes, the flour weight
/// does not (FlourSubstitution).
struct FlourSubstitutionCalculator: View {
    @State var gramsText = "500"
    @State var sourceID = FlourSubstitution.wheat550.id
    @State var targetID = FlourSubstitution.flours(of: .spelt).first { $0.milling == .type(630) }?.id
        ?? FlourSubstitution.wheat550.id

    private var grams: Double { Double(gramsText.filter(\.isNumber)) ?? 0 }
    private var source: FlourSubstitution.Flour {
        FlourSubstitution.catalog.first { $0.id == sourceID } ?? FlourSubstitution.wheat550
    }
    private var target: FlourSubstitution.Flour {
        FlourSubstitution.catalog.first { $0.id == targetID } ?? FlourSubstitution.wheat550
    }

    /// "+4 %" — what a flour binds beyond wheat 550.
    private func extraWaterText(_ share: Double) -> String {
        let percent = Int((share * 100).rounded())
        if percent == 0 { return "±0\u{00A0}%" }
        return percent > 0 ? "+\(percent)\u{00A0}%" : "−\(-percent)\u{00A0}%"
    }

    var body: some View {
        Form {
            Section {
                CalculatorResult(title: "Wasser anpassen",
                                 value: gramsDeltaText(FlourSubstitution.waterDelta(grams: grams, from: source, to: target))) {
                    Text(verbatim: "\(source.title) \(extraWaterText(source.extraWater)) → \(target.title) \(extraWaterText(target.extraWater))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Section {
                HStack {
                    Text("Menge")
                    Spacer()
                    TextField("Menge", text: $gramsText)
                        .keyboardType(.numberPad)
                        .frame(width: 96)
                    Text(verbatim: "g")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Mehl")
            }

            Section {
                FlourChoice(title: "Im Rezept", flourID: $sourceID)
            }

            Section {
                FlourChoice(title: "Ersetzen durch", flourID: $targetID)
            }

            let hints = FlourSubstitution.hints(from: source, to: target, ryeShareAfter: nil)
            if !hints.isEmpty {
                Section {
                    ForEach(hints) { hint in
                        Label {
                            flourHintText(hint)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                    }
                } header: {
                    Text("Worauf achten")
                }
            }

            Section {
                Text("Richtwerte: Mehle werden 1:1 nach Gewicht getauscht, nur das Wasser ändert sich. Wie viel ein Mehl bindet, schwankt je nach Mühle und Ernte – der Teig hat das letzte Wort.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mehl ersetzen")
    }

}

/// The flour hints in words, as on the iPhone; shared by the calculator
/// and the sheet of a recipe line.
func flourHintText(_ hint: FlourSubstitution.Hint) -> Text {
    switch hint {
    case .speltHandling:
        return Text("Dinkelteig kürzer und schonender kneten, lieber dehnen und falten – er neigt zum Überkneten und wird sonst trocken.")
    case .speltSoaker:
        return Text("Dinkel bindet Wasser langsamer: Ein Quell- oder Kochstück aus einem Teil des Mehls hält die Krume saftig.")
    case .ryeAcidify:
        let share = FlourSubstitution.ryeAcidifyShare.formatted(.percent)
        return Text("Roggen hat kein Klebergerüst: Ab etwa \(share) Roggenanteil den Teig mit Sauerteig versäuern, sonst wird die Krume klitschig.")
    case .ryeMixOnly:
        return Text("Bei über der Hälfte Roggen den Teig nur mischen statt kneten, mit nassen Händen formen und kräftig versäuern.")
    case .emmer:
        return Text("Emmer hat einen weichen Kleber: kurz kneten, kurze Gare, am sichersten in der Kastenform backen.")
    case .einkorn:
        return Text("Einkorn bindet wenig Wasser und ist klebrig: deutlich weniger Wasser, kaum kneten, Kastenform statt freigeschoben.")
    case .durumAutolyse:
        return Text("Hartweizen quillt langsam: 30–60 Minuten Autolyse einplanen; der Teig wird fester und gelblich.")
    case .wholeGrainSoak:
        return Text("Vollkorn braucht Zeit zum Quellen: Autolyse oder ein Brüh-/Quellstück einplanen; die Krume wird dichter.")
    case .wheatKnead:
        return Text("Weizen hat mehr Kleber als Dinkel, Emmer oder Einkorn: etwas länger kneten, bis der Teig ein Fenster zieht.")
    case .addWaterGradually:
        return Text("Das zusätzliche Wasser nach und nach einarbeiten und nach Teiggefühl korrigieren – Mehle schwanken je nach Mühle und Ernte.")
    }

}

// MARK: - Starter TA

/// A starter of another TA in place of the recipe's: the flour it brings
/// stays the same, starter and water shift against each other
/// (StarterYieldAdjustment).
struct StarterYieldCalculator: View {
    @State var gramsText = "100"
    @State var sourceYield = 150
    @State var targetYield = AppSettings.storedStarterDoughYield

    private var grams: Double { Double(gramsText.filter(\.isNumber)) ?? 0 }
    private var presets: [Int] { AppSettings.storedStarterDoughYieldPresets }

    var body: some View {
        let starterAfter = StarterYieldAdjustment.starterGrams(grams: grams, from: Double(sourceYield), to: Double(targetYield))
        let waterDelta = StarterYieldAdjustment.waterDelta(grams: grams, from: Double(sourceYield), to: Double(targetYield))
        Form {
            Section {
                CalculatorResult(title: "Anstellgut einsetzen", value: "\(Int(starterAfter.rounded())) g") {
                    Text("Wasser im Teig: \(gramsDeltaText(waterDelta))")
                    Text(verbatim: "\(Int(grams.rounded())) g TA \(sourceYield) → TA \(targetYield)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text("Menge")
                    Spacer()
                    TextField("Menge", text: $gramsText)
                        .keyboardType(.numberPad)
                        .frame(width: 96)
                    Text(verbatim: "g")
                        .foregroundStyle(.secondary)
                }
                Stepper(value: $sourceYield,
                        in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield, step: 5) {
                    ValueLabel(title: "TA im Rezept", value: "TA \(sourceYield)")
                }
            } header: {
                Text("Im Rezept")
            }

            Section {
                // The TAs one keeps starters at, from the settings, as quick
                // picks; the stepper for any other value.
                Text("Mein Anstellgut")
                Picker("Mein Anstellgut", selection: $targetYield) {
                    ForEach(presets, id: \.self) { preset in
                        Text(verbatim: String(preset)).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Stepper(value: $targetYield,
                        in: AppSettings.minimumStarterDoughYield...AppSettings.maximumStarterDoughYield, step: 5) {
                    ValueLabel(title: "Genauer Wert", value: "TA \(targetYield)")
                }
            } header: {
                Text("Vorhanden")
            }

            let hints = StarterYieldAdjustment.hints(from: Double(sourceYield), to: Double(targetYield), yieldSource: .name)
            if !hints.isEmpty {
                Section {
                    ForEach(hints) { hint in
                        Label {
                            starterHintText(hint)
                        } icon: {
                            Image(systemName: "info.circle")
                        }
                    }
                } header: {
                    Text("Worauf achten")
                }
            }

            Section {
                Text("Das Mehl aus dem Anstellgut bleibt gleich; nur Anstellgut und Wasser verschieben sich gegeneinander. Teigausbeute und Gesamtgewicht des Teigs ändern sich dadurch nicht.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Anstellgut-TA anpassen")
    }

}

/// The starter hints in words, as on the iPhone; shared by the calculator
/// and the sheet of a recipe line.
func starterHintText(_ hint: StarterYieldAdjustment.Hint) -> Text {
    switch hint {
    case .softer:
        return Text("Weicheres Anstellgut (höhere TA) gärt schneller und säuert milder – die Reifezeit des Sauerteigs eher etwas kürzer ansetzen.")
    case .firmer:
        return Text("Festeres Anstellgut (niedrigere TA) arbeitet langsamer und säuert kräftiger – etwas mehr Reifezeit einplanen.")
    case .bigStep:
        return Text("Bei großen TA-Unterschieden lohnt es sich, das Anstellgut vorher mit ein bis zwei Fütterungen auf die gewünschte TA umzustellen.")
    case .assumedYield:
        return Text("Das Rezept nennt keine TA für sein Anstellgut; angenommen ist die TA aus den Einstellungen. Steht sie im Rezept, trage sie in den Zutatennamen ein, etwa „Anstellgut TA 150“.")
    }

}
