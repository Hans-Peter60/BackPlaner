import BakePlannerCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The parts of a recipe page that own and public recipes share: the
/// picture, and the components, total ingredients and steps at the amount
/// chosen (RecipePrintData, the preparation the iOS app prints from).
struct RecipePicture: View {
    let data: Data?

    var body: some View {
        #if canImport(UIKit) || os(Android)
        if let data, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        #endif
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
