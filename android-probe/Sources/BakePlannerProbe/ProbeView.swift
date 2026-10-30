//
//  ProbeView.swift
//  BakePlannerProbe
//
//  One screen that exercises what the BakePlanner views use most: a form
//  with steppers and a toggle, sections, lists, formatted numbers and dates,
//  and an @Observable model. Plus the logic copied from the app, so its
//  results can be compared with the iPhone at a glance. SkipFuseUI is
//  SwiftUI on iOS and its Android counterpart there.
//

import Foundation
import SkipFuseUI

struct ProbeView: View {
    // Not private: Skip Fuse cannot bridge private state to Android.
    @State var recipe = ProbeRecipe.sample
    @State var now = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Erinnerungen") {
                    NavigationLink("Erinnerungen testen") {
                        NotificationProbeView()
                    }
                }

                Section("Teigtemperatur") {
                    Stepper("Zieltemperatur: \(recipe.targetDoughTemperature) °C",
                            value: $recipe.targetDoughTemperature, in: 18...30)
                    Stepper("Raum: \(recipe.roomTemperature) °C",
                            value: $recipe.roomTemperature, in: 10...35)
                    Stepper("Mehl: \(recipe.flourTemperature) °C",
                            value: $recipe.flourTemperature, in: 5...35)
                    Stepper("Reibung: \(recipe.frictionFactor)",
                            value: $recipe.frictionFactor, in: 0...10)
                    Toggle("Mit Vorteig", isOn: $recipe.usesPreferment)
                    if recipe.usesPreferment {
                        Stepper("Vorteig: \(recipe.prefermentTemperature) °C",
                                value: $recipe.prefermentTemperature, in: 5...35)
                    }
                    HStack {
                        Text("Wassertemperatur")
                        Spacer()
                        Text("\(recipe.waterTemperature) °C")
                            .bold()
                            .foregroundStyle(feasibilityColor)
                    }
                }

                Section("Zutaten (Namen bereinigt)") {
                    ForEach(recipe.ingredients, id: \.self) { ingredient in
                        VStack(alignment: .leading) {
                            Text(IngredientNameNormalizer.displayName(ingredient))
                            Text(ingredient)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Gerade dran") {
                    Text(currentStepText)
                }

                Section("Sicherungsdatei vom iPhone") {
                    Text(backupText)
                }
            }
            .navigationTitle("BakePlanner-Probe")
        }
    }

    private var feasibilityColor: Color {
        switch DoughTemperatureCalculator.feasibility(ofWaterTemperature: recipe.waterTemperature) {
        case .ok: return .primary
        case .tooCold: return .blue
        case .tooHot: return .red
        }
    }

    /// Three steps around now: one due 20 minutes ago, two ahead.
    private var currentStepText: String {
        let steps = [("Teig falten", -20), ("Formen", 40), ("Backen", 120)].map {
            (name: $0.0, date: now.addingTimeInterval(TimeInterval($0.1 * 60)))
        }
        guard let current = CurrentStepRule.currentStep(in: steps, at: now, date: { $0.date }) else {
            return "Nichts geplant"
        }
        let time = current.step.date.formatted(date: .omitted, time: .shortened)
        return "\(current.step.name) um \(time)" + (current.isDue ? " – fällig" : "")
    }

    private var backupText: String {
        do {
            let file = try RecipeImport.decodeFile(Data(ProbeRecipe.sampleBackup.utf8))
            guard let first = file.recipes.first else { return "Keine Rezepte in der Datei" }
            let weight = first.totalWeight.formatted(.number.precision(.fractionLength(0...1)))
            return "\(first.name): \(first.components.count) Komponente(n), \(first.instructions.count) Schritte, \(weight) g"
        } catch {
            return "Fehler: \(error.localizedDescription)"
        }
    }
}
