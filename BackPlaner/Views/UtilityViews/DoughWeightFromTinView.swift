//
//  DoughWeightFromTinView.swift
//  BackPlaner
//
//  How much dough a tin or a proofing basket takes (DoughWeightFromTin),
//  and the way on to a recipe scaled to that weight. The measures and the
//  dough type are kept between visits: a baker has a few tins, not a new
//  one each time.
//

import BakePlannerCore
import CoreData
import SwiftUI

struct DoughWeightFromTinView: View {

    enum Shape: String, CaseIterable, Identifiable {
        case loafTin, roundTin, roundBasket, ovalBasket
        var id: String { rawValue }
    }

    @AppStorage(AppSettingsKeys.tinShape) private var shapeRaw = Shape.loafTin.rawValue
    @AppStorage(AppSettingsKeys.tinLengthCm) private var lengthCm = 30
    @AppStorage(AppSettingsKeys.tinWidthCm) private var widthCm = 11
    @AppStorage(AppSettingsKeys.tinHeightCm) private var heightCm = 8
    @AppStorage(AppSettingsKeys.tinDiameterCm) private var diameterCm = 22
    @AppStorage(AppSettingsKeys.tinDoughType) private var doughTypeRaw = DoughWeightFromTin.DoughType.mixed.rawValue
    /// Grams per millilitre as a whole percentage, so a stepper can hold it.
    @AppStorage(AppSettingsKeys.tinFillPercent) private var fillPercent = 45

    @State private var showsRecipePicker = false
    /// The recipe chosen to be scaled, opened on top of the calculator.
    @State private var scaledRecipe: ScaledRecipe?

    private struct ScaledRecipe: Identifiable, Hashable {
        let recipe: Recipe
        let grams: Int
        var id: NSManagedObjectID { recipe.objectID }
    }

    private var shape: Shape { Shape(rawValue: shapeRaw) ?? .loafTin }
    private var doughType: DoughWeightFromTin.DoughType {
        DoughWeightFromTin.DoughType(rawValue: doughTypeRaw) ?? .mixed
    }
    private var fillFactor: Double { Double(fillPercent) / 100 }

    private var isBasket: Bool { shape == .roundBasket || shape == .ovalBasket }

    private var volumeMilliliters: Double {
        switch shape {
        case .loafTin:
            return DoughWeightFromTin.volumeMilliliters(lengthCm: Double(lengthCm), widthCm: Double(widthCm), heightCm: Double(heightCm))
        case .roundTin:
            return DoughWeightFromTin.volumeMilliliters(diameterCm: Double(diameterCm), heightCm: Double(heightCm))
        case .roundBasket, .ovalBasket:
            return 0
        }
    }

    private var basketNominalGrams: Int {
        switch shape {
        case .roundBasket: return DoughWeightFromTin.basketNominalGrams(shape: .round, measureCm: Double(diameterCm))
        case .ovalBasket:  return DoughWeightFromTin.basketNominalGrams(shape: .oval, measureCm: Double(lengthCm))
        case .loafTin, .roundTin: return 0
        }
    }

    private var doughGrams: Int {
        isBasket
            ? DoughWeightFromTin.basketDoughGrams(nominalGrams: basketNominalGrams, doughType: doughType)
            : DoughWeightFromTin.doughGrams(volumeMilliliters: volumeMilliliters, fillFactor: fillFactor)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Text("Teigeinlage")
                        .font(Theme.bodyFont(14))
                        .foregroundColor(Theme.subtitle)

                    Text(verbatim: "\(doughGrams.formatted(.number.locale(AppSettings.locale))) g")
                        .font(Theme.brandFont(40))
                        .foregroundColor(Theme.cardTitle)

                    Group {
                        if isBasket {
                            Text("Nennwert des Körbchens: \(basketNominalGrams.formatted(.number.locale(AppSettings.locale))) g")
                            Text("Anpassung für die Teigart: \(Self.percentText(doughType.basketFactor))")
                        } else {
                            Text("Volumen \(Self.litresText(volumeMilliliters)) × \(Self.factorText(fillFactor)) g/ml")
                        }
                    }
                    .font(Theme.bodyFont(13))
                    .foregroundColor(Theme.subtitle)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)

            Section("Form") {
                Picker("Form", selection: $shapeRaw) {
                    Text("Kastenform").tag(Shape.loafTin.rawValue)
                    Text("Runde Form").tag(Shape.roundTin.rawValue)
                    Text("Gärkörbchen rund").tag(Shape.roundBasket.rawValue)
                    Text("Gärkörbchen oval").tag(Shape.ovalBasket.rawValue)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("tin.shape")
            }

            Section(isBasket ? "Maß am oberen Rand" : "Innenmaße") {
                switch shape {
                case .loafTin:
                    measureStepper("Länge", value: $lengthCm, range: 10...50)
                    measureStepper("Breite", value: $widthCm, range: 5...30)
                    measureStepper("Höhe", value: $heightCm, range: 4...20)
                case .roundTin:
                    measureStepper("Durchmesser", value: $diameterCm, range: 10...40)
                    measureStepper("Höhe", value: $heightCm, range: 4...20)
                case .roundBasket:
                    measureStepper("Durchmesser", value: $diameterCm, range: 12...40)
                case .ovalBasket:
                    measureStepper("Länge", value: $lengthCm, range: 15...50)
                }
            }

            Section {
                Picker("Teigart", selection: $doughTypeRaw) {
                    Text("Weizen hell, Toast").tag(DoughWeightFromTin.DoughType.lightWheat.rawValue)
                    Text("Mischbrot").tag(DoughWeightFromTin.DoughType.mixed.rawValue)
                    Text("Roggen, Vollkorn, Saaten").tag(DoughWeightFromTin.DoughType.ryeWholeGrain.rawValue)
                }
                .pickerStyle(.menu)
                .onChange(of: doughTypeRaw) { _, _ in
                    fillPercent = Int((doughType.fillFactor * 100).rounded())
                }

                if !isBasket {
                    Stepper(value: $fillPercent,
                            in: Int(DoughWeightFromTin.minimumFillFactor * 100)...Int(DoughWeightFromTin.maximumFillFactor * 100)) {
                        LabeledContent("Füllfaktor", value: "\(Self.factorText(fillFactor)) g/ml")
                    }
                }
            } header: {
                Text("Teig")
            } footer: {
                if isBasket {
                    Text("Nennwerte, wie Körbchen-Anbieter sie angeben: 500 g bei Ø 18 cm, 750 g bei Ø 20 cm, 1.000 g bei Ø 22 cm, 1.500 g bei Ø 25 cm, 2.000 g bei Ø 28 cm; oval entsprechend 22, 25, 28, 32 und 35 cm Länge. Dazwischen rechnet die App linear. Roggenteig darf schwerer sein, lockerer Weizenteig leichter.")
                } else {
                    Text("Richtwerte: Weizen hell und Toast 0,35–0,40 g je ml, Mischbrot etwa 0,45, Roggen, Vollkorn und Saaten 0,50–0,55. Innen messen, bei schrägen Wänden die Breite auf halber Höhe. Nach dem ersten Backen den Füllfaktor an Dein Ergebnis anpassen.")
                }
            }

            Section {
                Button {
                    showsRecipePicker = true
                } label: {
                    Label("Rezept auf dieses Gewicht skalieren", systemImage: "scalemass")
                }
                .disabled(doughGrams <= 0)
                .accessibilityIdentifier("tin.scaleRecipe")
            } footer: {
                Text("Öffnet das Rezept mit diesem Teiggewicht als Zielgewicht; Zutaten, Plan und Einkaufsliste rechnen damit.")
            }
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Teigeinlage aus der Form")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsRecipePicker) {
            RecipeChoiceSheet { recipe in
                scaledRecipe = ScaledRecipe(recipe: recipe, grams: doughGrams)
            }
        }
        .navigationDestination(item: $scaledRecipe) { chosen in
            RecipePageView(recipe: chosen.recipe, initialTargetWeight: chosen.grams)
        }
    }

    private func measureStepper(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title, value: "\(value.wrappedValue) cm")
        }
    }

    /// "2,6 l"
    private static func litresText(_ milliliters: Double) -> String {
        (milliliters / 1000).formatted(.number.precision(.fractionLength(1)).locale(AppSettings.locale)) + " l"
    }

    /// "0,45"
    private static func factorText(_ factor: Double) -> String {
        factor.formatted(.number.precision(.fractionLength(2)).locale(AppSettings.locale))
    }

    /// "+20 %", "−10 %", "±0 %"
    private static func percentText(_ factor: Double) -> String {
        let percent = Int(((factor - 1) * 100).rounded())
        if percent == 0 { return "±0\u{00A0}%" }
        return percent > 0 ? "+\(percent)\u{00A0}%" : "−\(-percent)\u{00A0}%"
    }
}

/// One of the user's own recipes, picked by name.
private struct RecipeChoiceSheet: View {
    let onChoose: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)])
    private var recipes: FetchedResults<Recipe>

    var body: some View {
        NavigationStack {
            Group {
                if recipes.isEmpty {
                    ContentUnavailableView("Keine eigenen Rezepte", systemImage: "book.closed")
                } else {
                    List(recipes) { recipe in
                        Button {
                            onChoose(recipe)
                            dismiss()
                        } label: {
                            Text(recipe.name)
                                .font(Theme.bodyFont(16))
                                .foregroundColor(Theme.cardTitle)
                        }
                    }
                }
            }
            .navigationTitle("Rezept wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
