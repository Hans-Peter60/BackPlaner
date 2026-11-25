import BakePlannerCore
import Foundation
import SwiftUI

/// "Aus Text": recipe text the person pasted — or selected on a page and
/// shared with BakePlanner — becomes a new recipe, which opens in the
/// editor, as the iPhone does: with the cloud AI when the user chose it
/// and agreed to it (Cloud Function analyzeRecipeText), else, or when the
/// cloud fails, read by the headings a recipe is printed with
/// (PastedRecipeText in BakePlannerCore). Android has no on-device model
/// in between.
struct TextRecipeImportView: View {
    let model: AppModel
    /// Hands the imported recipe and what to say about it to the list,
    /// which opens the editor with them.
    let onImport: (RecipeExportData, Text?) -> Void
    /// Text another app shared; the view starts with it filled in.
    var initialText: String? = nil
    @State var text = ""
    @State var address = ""
    @State var isLoading = false
    @State var failure: String?
    @Environment(\.dismiss) var dismiss

    /// The cloud is chosen but not agreed to yet: the consent replaces the
    /// import button.
    private var needsConsent: Bool {
        model.usesCloudAnalysis && !model.allowsCloudAnalysis
    }

    private var hasEnoughText: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= PastedRecipeText.minimumCharacters
    }

    var body: some View {
        Form {
            Section {
                // A TextEditor has no prompt of its own; the hint sits over
                // it until the first character and lets taps through.
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                    if text.isEmpty {
                        Text("Hier den Rezepttext einfügen …")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
                if !text.isEmpty, !hasEnoughText {
                    Text("Das ist noch zu wenig Text für ein Rezept.")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.red)
                }
                if isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(model.usesCloudAnalysis && model.allowsCloudAnalysis
                             ? LocalizedStringKey("Rezept wird in der Cloud analysiert …")
                             : LocalizedStringKey("Text wird analysiert …"))
                    }
                }
                if let failure {
                    Text(verbatim: failure)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.red)
                }
            } header: {
                Text("Rezepttext")
            } footer: {
                Text("Markiere auf der Seite am besten nur das Rezept, von der Überschrift bis zum letzten Arbeitsschritt. Für den privaten Gebrauch ist der Import unbedenklich; veröffentliche fremde Rezepte nur mit Erlaubnis.")
            }

            Section {
                TextField("https://…", text: $address)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Internetadresse (optional)")
            } footer: {
                Text("Die Adresse wird als Link im Rezept gespeichert.")
            }

            Section {
                Picker("Analyseart", selection: Binding(get: { model.usesCloudAnalysis },
                                                         set: { model.usesCloudAnalysis = $0 })) {
                    Text("Geschützte Cloud-KI").tag(true)
                    Text("Nur auf diesem Gerät").tag(false)
                }
                .pickerStyle(.segmented)
                Text(model.usesCloudAnalysis
                     ? LocalizedStringKey("Der eingefügte Text wird verschlüsselt über den geschützten BackPlaner-Server von Google Vertex AI analysiert. Dafür ist einmalig Deine Einwilligung nötig.")
                     : LocalizedStringKey("Der Text verlässt das Gerät nicht. Die App liest Zutaten und Schritte nach festen Regeln; Überschriften wie „Zutaten“ und „Zubereitung“ helfen dabei."))
                    .font(AppFont.caption)
            } header: {
                Text("Analyseart")
            }

            if needsConsent {
                // The iPhone's consent before the first cloud analysis.
                Section {
                    Text("Analyse mit Google Vertex AI (Gemini)")
                        .font(AppFont.headline)
                    Text("Der von Dir eingefügte Rezepttext und, falls angegeben, die Adresse seiner Quelle werden verschlüsselt an den geschützten Firebase-Endpunkt von BackPlaner und von dort an Google Vertex AI übertragen. Google ist dabei ein externer KI-Anbieter. Zur Absicherung und Nutzungsbegrenzung werden außerdem eine pseudonyme Firebase-Nutzerkennung, der App-Check-Nachweis sowie Anfragezeit und -anzahl verarbeitet.")
                    Text("Der Text wird ausschließlich analysiert, um daraus einen Rezeptentwurf mit Zutaten und Arbeitsschritten zu erstellen. BackPlaner speichert den übertragenen Text nicht in Firebase Storage oder in der Rezept-Datenbank.")
                    Text("Du kannst stattdessen jederzeit die lokale Analyse verwenden. Dann verlässt der Text Dein Gerät nicht.")
                    Button("Zustimmen und mit Cloud-KI analysieren") {
                        model.allowsCloudAnalysis = true
                        Task { await importText() }
                    }
                    .disabled(isLoading || !hasEnoughText)
                    Button("Nur lokal analysieren") {
                        model.usesCloudAnalysis = false
                        Task { await importText() }
                    }
                    .disabled(isLoading || !hasEnoughText)
                    Text("Du kannst die Einwilligung später unter Einstellungen › Datenschutz & KI widerrufen.")
                        .font(AppFont.caption)
                } header: {
                    Text("Vor der ersten Cloud-Analyse")
                }
            }
        }
        .navigationTitle("Rezept aus Text importieren")
        .task {
            if let initialText, text.isEmpty {
                text = initialText
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Importieren") {
                    Task { await importText() }
                }
                .disabled(isLoading || needsConsent || !hasEnoughText)
            }
        }
    }

    /// The source address when one was given and reads like one.
    private var sourceURL: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return RecipeWebPageLoader.normalizedURL(from: trimmed)
    }

    private func importText() async {
        failure = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let cleaned = try PastedRecipeText.validated(text)
            let firstLine = String((cleaned.components(separatedBy: "\n").first ?? "").prefix(80))
            logger.info("text import: \(cleaned.count) characters")

            var recipe: RecipeFB?
            var notice: Text?
            var cloudFailed = false
            if model.usesCloudAnalysis && model.allowsCloudAnalysis {
                do {
                    let analysis = try await PublicRecipeService.analyzeRecipeText(cleaned, sourceURL: sourceURL)
                    let cloudRecipe = analysis.recipe.makeRecipe()
                    if cloudRecipe.name.isEmpty { cloudRecipe.name = firstLine }
                    if RecipeImportCheck.hasRecipeData(cloudRecipe) {
                        RecipeImportPlan.groupComponentPreparations(in: cloudRecipe)
                        recipe = cloudRecipe
                        let warnings = analysis.recipe.warnings.joined(separator: "\n")
                        notice = warnings.isEmpty ? nil : Text(verbatim: warnings)
                    } else {
                        cloudFailed = true
                    }
                } catch {
                    logger.error("text import: cloud AI failed: \(error)")
                    cloudFailed = true
                }
            }
            if recipe == nil {
                guard let structured = PastedRecipeText.structuredRecipe(from: cleaned) else {
                    throw RecipeTextImportError.noRecipeFound
                }
                let ruleRecipe = structured.makeRecipe()
                if ruleRecipe.name.isEmpty { ruleRecipe.name = firstLine }
                RecipeImportPlan.groupComponentPreparations(in: ruleRecipe)
                recipe = ruleRecipe
                notice = cloudFailed
                    ? Text("Die Cloud-KI war nicht erreichbar. Das Rezept wurde ohne KI nach festen Regeln aus dem Text übernommen. Komponenten, Zutaten und Dauern bitte besonders prüfen.")
                    : Text("Das Rezept wurde ohne KI nach festen Regeln aus dem Text übernommen. Komponenten, Zutaten und Dauern bitte besonders prüfen.")
            }
            guard let imported = recipe else { throw RecipeTextImportError.noRecipeFound }
            if let sourceURL { imported.urlLink = sourceURL.absoluteString }
            RecipeImportStepText.applyDefaultDuration(to: imported.instructions)
            onImport(RecipeExportData(recipeFB: imported, imageData: nil), notice)
            dismiss()
        } catch {
            logger.error("text import failed: \(error)")
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
