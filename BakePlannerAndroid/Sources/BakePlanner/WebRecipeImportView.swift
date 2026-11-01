import BakePlannerCore
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// "Von einer Internetseite": loads a recipe page on the device and turns
/// its structured recipe data (schema.org) into a new recipe, which opens
/// in the editor — as the iPhone does when no AI is used
/// (RecipeWebPageLoader in BakePlannerCore). Pages without such data are
/// not read yet; that needs the cloud AI (step 17c).
struct WebRecipeImportView: View {
    /// Hands the imported recipe to the list, which opens the editor with it.
    let onImport: (RecipeExportData) -> Void
    @State var address = ""
    @State var isLoading = false
    @State var failure: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section {
                TextField("https://…", text: $address)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if isLoading {
                    ProgressView()
                }
                if let failure {
                    Text(verbatim: failure)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
            } header: {
                Text("Internetadresse")
            } footer: {
                Text("Die Seite wird auf diesem Gerät geladen. Übernommen werden die Rezeptdaten, die die Seite selbst angibt; anschließend lässt sich alles bearbeiten.")
            }
        }
        .navigationTitle("Rezept von einer Internetseite importieren")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Importieren") {
                    Task { await importPage() }
                }
                .disabled(isLoading || address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func importPage() async {
        failure = nil
        guard let url = RecipeWebPageLoader.normalizedURL(from: address) else {
            failure = RecipeWebImportError.invalidAddress.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await RecipeWebPageLoader.load(url)
            guard let structured = page.structuredRecipe else {
                throw RecipeWebImportError.noRecipeFound
            }
            let recipe = structured.makeRecipe()
            recipe.urlLink = page.url.absoluteString
            if recipe.sourceLanguage.isEmpty { recipe.sourceLanguage = page.language }
            if recipe.name.isEmpty { recipe.name = page.title }
            RecipeImportStepText.applyDefaultDuration(to: recipe.instructions)
            let picture = await Self.picture(from: page.imageURL)
            let content = RecipeExportData(recipeFB: recipe, imageData: picture)
            onImport(content)
            dismiss()
        } catch {
            failure = (error as? RecipeWebImportError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The page's photo as the app keeps pictures (PhotoShrinker), when it
    /// is one and not just an icon.
    private static func picture(from url: URL?) async -> Data? {
        guard let data = await RecipeWebPageLoader.loadImageData(from: url) else { return nil }
        #if canImport(UIKit) || os(Android)
        guard let image = UIImage(data: data),
              Double(image.size.width) >= RecipeWebPageLoader.minimumImageEdge,
              Double(image.size.height) >= RecipeWebPageLoader.minimumImageEdge else { return nil }
        #endif
        return PhotoShrinker.pickedPhoto(data)
    }
}
