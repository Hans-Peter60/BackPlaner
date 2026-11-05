import BakePlannerCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The parts of a recipe page that own and public recipes share: the
/// picture, the link to the recipe's source, and the components, total
/// ingredients and steps at the amount chosen (RecipePrintData, the
/// preparation the iOS app prints from).
struct RecipePicture: View {
    let data: Data?
    /// A tap shows the picture large, as on the iPhone.
    @State var showsLarge = false

    var body: some View {
        #if canImport(UIKit) || os(Android)
        if let data, let image = UIImage(data: data) {
            Button {
                showsLarge = true
            } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .appSheet(isPresented: $showsLarge) {
                NavigationStack {
                    LargePictureView(image: image)
                }
            }
        }
        #endif
    }
}

#if canImport(UIKit) || os(Android)
/// The recipe picture filling the screen, on a dark background.
struct LargePictureView: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Schließen") {
                    dismiss()
                }
            }
        }
    }
}
#endif

/// "Link zum Rezept": opens the recipe's source in the browser, when the
/// recipe names one. SkipUI has no Link view, so a button opens the address.
struct RecipeLinkRow: View {
    let urlLink: String?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if let link = urlLink?.trimmingCharacters(in: .whitespacesAndNewlines), !link.isEmpty,
           let url = URL(string: link), url.scheme != nil {
            Button {
                Task { _ = await UIApplication.shared.open(url) }
            } label: {
                // "safari", not "link": SkipUI draws no link symbol (a warning triangle instead).
                Label("Link zum Rezept", systemImage: "safari")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent(colorScheme))
            .font(AppFont.subheadline)
        }
    }
}

struct RecipeLineSections: View {
    let page: RecipePrintData
    /// The recipe behind the page, when its flour and starter lines are to
    /// be tappable (own recipes): the columns of `page` come from the same
    /// recipe, so a line's indices name the same ingredient in both.
    var content: RecipeExportData? = nil
    var onFlourTap: ((Int, Int) -> Void)? = nil
    var onStarterTap: ((Int, Int) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme

    private var columns: [ComponentColumn] {
        content.map { ComponentColumn.columns(of: $0) } ?? []
    }

    /// What a tap on a line does, as the iPhone's one-line hint.
    private var tapHint: LocalizedStringKey? {
        let names = columns.map(\.name)
        let flour = onFlourTap != nil && columns.contains { $0.ingredients.contains { FlourSubstitution.recognize($0.name) != nil } }
        let starter = onStarterTap != nil && columns.contains { $0.ingredients.contains {
            StarterYieldAdjustment.recognize($0, componentNames: names) != nil } }
        switch (flour, starter) {
        case (true, true): return "Tippe auf ein Mehl, um es zu ersetzen, oder auf das Anstellgut, um seine TA anzupassen."
        case (true, false): return "Tippe auf ein Mehl, um es zu ersetzen."
        case (false, true): return "Tippe auf das Anstellgut, um seine TA anzupassen."
        case (false, false): return nil
        }
    }

    var body: some View {
        let columns = self.columns
        let names = columns.map(\.name)
        VStack(alignment: .leading, spacing: 16) {
            section("Komponenten") {
                if let tapHint {
                    Text(tapHint)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(page.components.enumerated()), id: \.offset) { componentIndex, component in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: component.name)
                            .font(AppFont.headline)
                        ForEach(Array(component.lines.enumerated()), id: \.offset) { ingredientIndex, line in
                            let ingredient = columns.indices.contains(componentIndex)
                                && columns[componentIndex].ingredients.indices.contains(ingredientIndex)
                                ? columns[componentIndex].ingredients[ingredientIndex] : nil
                            if let onFlourTap, let ingredient, FlourSubstitution.recognize(ingredient.name) != nil {
                                Button {
                                    onFlourTap(componentIndex, ingredientIndex)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(verbatim: line)
                                        Image(systemName: "arrow.forward.square")
                                            .font(AppFont.caption)
                                            .foregroundStyle(Palette.accent(colorScheme))
                                    }
                                }
                                .buttonStyle(.plain)
                            } else if let onStarterTap, let ingredient,
                                      StarterYieldAdjustment.recognize(ingredient, componentNames: names) != nil {
                                Button {
                                    onStarterTap(componentIndex, ingredientIndex)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(verbatim: line)
                                        Image(systemName: "arrow.clockwise.circle")
                                            .font(AppFont.caption)
                                            .foregroundStyle(Palette.accent(colorScheme))
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(verbatim: line)
                            }
                        }
                    }
                }
            }

            section("Gesamtzutaten") {
                ForEach(Array(page.totalLines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                }
            }

            section("Verarbeitungsschritte") {
                ForEach(Array(page.steps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: step.number)
                            .bold()
                            .frame(width: 36, alignment: .leading)
                        Text(verbatim: step.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: step.duration)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// A block of the recipe page on its own card, as on the iPhone.
    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.bold(.title3))
                .foregroundStyle(Palette.accentText(colorScheme))
            content()
        }
        .foregroundStyle(Palette.cardTitle(colorScheme))
        .cardStyle()
    }
}

/// Portion factor or target dough weight — two ways to the same scale, as
/// the iPhone's ServingScaleControl: the stepper counts in halves, a weight
/// typed in scales every amount to it and the factor shows "–"; stepping
/// again clears the weight.
struct AmountControl: View {
    /// The scale in force, 1 being the recipe as stored.
    @Binding var scale: Double
    /// The recipe's total weight at factor 1.
    let baseWeight: Double
    /// The dough type the tin calculator starts with, read from the recipe.
    var suggestedDoughType: DoughWeightFromTin.DoughType? = nil
    @State var halves = 2
    @State var weightText = ""
    /// The tin calculator as a sheet; its result lands in the weight field.
    @State var showsTinCalculator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $halves, in: 1...20) {
                HStack {
                    Text("Menge")
                    Text(verbatim: "× " + (weightText.isEmpty ? RecipeDetailView.factorText(scale) : "–"))
                        .bold()
                }
            }
            .onChange(of: halves) { _, halves in
                weightText = ""
                scale = ServingScale.factor(servingSize: halves, targetWeight: nil, baseWeight: baseWeight)
            }
            HStack(spacing: 6) {
                Text("Teiggewicht")
                // The placeholder is the weight at the current factor, as
                // on the iPhone; a plain String, so no catalog key arises.
                TextField(String(Int((baseWeight * scale).rounded())), text: $weightText)
                    .keyboardType(.numberPad)
                    .frame(width: 110)
                Text(verbatim: "g")
                // The weight from a tin or a basket, without leaving the
                // recipe: the calculator opens as a sheet and fills the field.
                Button {
                    showsTinCalculator = true
                } label: {
                    Image(systemName: "scalemass")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Teigeinlage aus der Form")
            }
            .onChange(of: weightText) { _, text in
                let digits = text.filter(\.isNumber)
                if digits != text {
                    weightText = digits
                    return
                }
                scale = ServingScale.factor(servingSize: halves, targetWeight: Int(digits), baseWeight: baseWeight)
            }
        }
        .appSheet(isPresented: $showsTinCalculator) {
            NavigationStack {
                DoughWeightFromTinCalculator(onApply: { grams in
                    weightText = String(grams)
                    showsTinCalculator = false
                }, suggestedDoughType: suggestedDoughType)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            showsTinCalculator = false
                        }
                    }
                }
            }
        }
    }
}
