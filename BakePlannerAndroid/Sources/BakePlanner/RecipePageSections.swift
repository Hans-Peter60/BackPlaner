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
                Label("Link zum Rezept", systemImage: "link")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent(colorScheme))
            .font(.subheadline)
        }
    }
}

struct RecipeLineSections: View {
    let page: RecipePrintData
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("Komponenten") {
                ForEach(Array(page.components.enumerated()), id: \.offset) { _, component in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: component.name)
                            .font(.headline)
                        ForEach(Array(component.lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line)
                        }
                    }
                }
            }

            section("Gesamtzutaten:") {
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .bold()
                .foregroundStyle(Palette.accent(colorScheme))
            content()
        }
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
    @State var halves = 2
    @State var weightText = ""

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
    }
}
