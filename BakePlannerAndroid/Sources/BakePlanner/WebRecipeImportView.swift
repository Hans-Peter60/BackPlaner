import BakePlannerCore
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// "Von einer Internetseite": loads a recipe page on the device and turns it
/// into a new recipe, which opens in the editor — as the iPhone does:
/// with the cloud AI when the user chose it and agreed to it (Cloud
/// Function analyzeRecipeText), else, or when the cloud fails, from the
/// page's own structured recipe data (RecipeWebPageLoader in
/// BakePlannerCore). Android has no on-device model in between.
struct WebRecipeImportView: View {
    let model: AppModel
    /// Hands the imported recipe and what to say about it to the list,
    /// which opens the editor with them.
    let onImport: (RecipeExportData, Text?) -> Void
    @State var address = ""
    @State var isLoading = false
    @State var failure: String?
    @Environment(\.dismiss) var dismiss

    /// The cloud is chosen but not agreed to yet: the consent replaces the
    /// import button.
    private var needsConsent: Bool {
        model.usesCloudAnalysis && !model.allowsCloudAnalysis
    }

    var body: some View {
        Form {
            Section {
                TextField("https://…", text: $address)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(model.usesCloudAnalysis && model.allowsCloudAnalysis
                             ? LocalizedStringKey("Rezept wird in der Cloud analysiert …")
                             : LocalizedStringKey("Seite wird geladen …"))
                    }
                }
                if let failure {
                    Text(verbatim: failure)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                }
            } header: {
                Text("Internetadresse")
            } footer: {
                Text("Seiten mit Anmeldung, Bezahlschranke oder Cookie-Hinweis lassen sich oft nicht auslesen. Für den privaten Gebrauch ist der Import unbedenklich; veröffentliche fremde Rezepte nur mit Erlaubnis.")
            }

            Section {
                Picker("Analyseart", selection: Binding(get: { model.usesCloudAnalysis },
                                                         set: { model.usesCloudAnalysis = $0 })) {
                    Text("Geschützte Cloud-KI").tag(true)
                    Text("Nur auf diesem Gerät").tag(false)
                }
                .pickerStyle(.segmented)
                Text(model.usesCloudAnalysis
                     ? LocalizedStringKey("Der Rezepttext der Seite wird verschlüsselt über den geschützten BackPlaner-Server von Google Vertex AI analysiert. Dafür ist einmalig Deine Einwilligung nötig.")
                     : LocalizedStringKey("Der Seitentext verlässt das Gerät nicht. Übernommen werden nur die strukturierten Rezeptdaten der Seite."))
                    .font(.caption)
            } header: {
                Text("Analyseart")
            }

            if needsConsent {
                // The iPhone's consent before the first cloud analysis.
                Section {
                    Text("Analyse mit Google Vertex AI (Gemini)")
                        .font(.headline)
                    Text("Der Rezepttext der von Dir angegebenen Internetseite und ihre Adresse werden verschlüsselt an den geschützten Firebase-Endpunkt von BackPlaner und von dort an Google Vertex AI übertragen. Google ist dabei ein externer KI-Anbieter. Zur Absicherung und Nutzungsbegrenzung werden außerdem eine pseudonyme Firebase-Nutzerkennung, der App-Check-Nachweis sowie Anfragezeit und -anzahl verarbeitet.")
                    Text("Die Seite selbst wird von Deinem Gerät geladen. Der Text wird ausschließlich analysiert, um daraus einen Rezeptentwurf mit Zutaten und Arbeitsschritten zu erstellen. BackPlaner speichert den übertragenen Text nicht in Firebase Storage oder in der Rezept-Datenbank.")
                    Text("Du kannst stattdessen jederzeit die lokale Analyse verwenden. Dann verlässt der Seitentext Dein Gerät nicht.")
                    Button("Zustimmen und mit Cloud-KI analysieren") {
                        model.allowsCloudAnalysis = true
                        Task { await importPage() }
                    }
                    .disabled(isLoading || address.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Nur lokal analysieren") {
                        model.usesCloudAnalysis = false
                        Task { await importPage() }
                    }
                    .disabled(isLoading || address.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Du kannst die Einwilligung später unter Einstellungen › Datenschutz & KI widerrufen.")
                        .font(.caption)
                } header: {
                    Text("Vor der ersten Cloud-Analyse")
                }
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
                .disabled(isLoading || needsConsent || address.trimmingCharacters(in: .whitespaces).isEmpty)
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
            logger.info("web import \(page.url.absoluteString): structured recipe \(page.structuredRecipe != nil), \(page.structuredRecipe?.ingredientLines.count ?? 0) ingredients, page text \(page.readableText.count) characters")

            var recipe: RecipeFB?
            var notice: Text?
            var cloudFailed = false
            if model.usesCloudAnalysis && model.allowsCloudAnalysis {
                do {
                    let analysis = try await PublicRecipeService.analyzeRecipeText(page.analysisText, sourceURL: page.url)
                    let cloudRecipe = analysis.recipe.makeRecipe()
                    if RecipeImportCheck.hasRecipeData(cloudRecipe) {
                        RecipeImportPlan.groupComponentPreparations(in: cloudRecipe)
                        recipe = cloudRecipe
                        let warnings = analysis.recipe.warnings.joined(separator: "\n")
                        notice = warnings.isEmpty ? nil : Text(verbatim: warnings)
                    } else {
                        cloudFailed = true
                    }
                } catch {
                    logger.error("web import \(url.absoluteString): cloud AI failed: \(error)")
                    cloudFailed = true
                }
            }
            if recipe == nil {
                guard let structured = page.structuredRecipe else {
                    throw RecipeWebImportError.noRecipeFound
                }
                recipe = structured.makeRecipe()
                notice = cloudFailed
                    ? Text("Die Cloud-KI war nicht erreichbar. Das Rezept wurde ohne KI aus den strukturierten Daten der Seite übernommen. Komponenten und Dauern bitte besonders prüfen.")
                    : Text("Das Rezept wurde ohne KI aus den strukturierten Daten der Seite übernommen. Komponenten und Dauern bitte besonders prüfen.")
            }
            guard let imported = recipe else { throw RecipeWebImportError.noRecipeFound }
            imported.urlLink = page.url.absoluteString
            if imported.sourceLanguage.isEmpty { imported.sourceLanguage = page.language }
            if imported.name.isEmpty { imported.name = page.title }
            RecipeImportStepText.applyDefaultDuration(to: imported.instructions)
            let picture = await Self.picture(from: page.imageURL)
            onImport(RecipeExportData(recipeFB: imported, imageData: picture), notice)
            dismiss()
        } catch {
            logger.error("web import \(url.absoluteString) failed: \(error)")
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
