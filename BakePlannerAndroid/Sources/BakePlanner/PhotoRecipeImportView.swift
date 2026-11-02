import BakePlannerCore
import Foundation
import SkipKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// "Aus Fotos": the photographed pages of a recipe become a new recipe, which
/// opens in the editor — with the cloud AI (Cloud Function
/// analyzeRecipeImages), as the iPhone does when the cloud is chosen. Android
/// has no text recognition on the device yet, so without the cloud the
/// import stays out; the view says so. The first page becomes the recipe's
/// picture, as on the iPhone.
struct PhotoRecipeImportView: View {
    let model: AppModel
    /// Hands the imported recipe and what to say about it to the list,
    /// which opens the editor with them.
    let onImport: (RecipeExportData, Text?) -> Void
    @State var pages: [ImportPage] = []
    @State var picksPages = false
    @State var takesPhoto = false
    @State var pickedURLs: [URL] = []
    @State var pickedNames: [String] = []
    @State var pickedTypes: [String] = []
    @State var isAnalyzing = false
    @State var isPreparing = false
    @State var failure: String?
    @Environment(\.dismiss) var dismiss

    /// What the function accepts at most.
    static let maximumPages = 10

    /// One photographed page, as the app keeps pictures (PhotoShrinker).
    struct ImportPage: Identifiable {
        let id = UUID()
        let data: Data
    }

    /// The cloud is chosen but not agreed to yet: the consent replaces the
    /// import button.
    private var needsConsent: Bool {
        model.usesCloudAnalysis && !model.allowsCloudAnalysis
    }

    private var canImport: Bool {
        !pages.isEmpty && model.usesCloudAnalysis && !needsConsent && !isAnalyzing && !isPreparing
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    HStack(spacing: 12) {
                        PageThumbnail(data: page.data)
                        Text("Seite \(index + 1)")
                        Spacer()
                        Button(role: .destructive) {
                            pages.removeAll { $0.id == page.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(Text("Seite \(index + 1) entfernen"))
                    }
                }
                HStack(spacing: 16) {
                    Button("Bilder auswählen") {
                        picksPages = true
                    }
                    Button("Aufnehmen") {
                        takesPhoto = true
                    }
                }
                .disabled(pages.count >= Self.maximumPages || isAnalyzing || isPreparing)
                if isPreparing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Fotos werden vorbereitet …")
                    }
                }
                if isAnalyzing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Rezept wird in der Cloud analysiert …")
                    }
                }
                if let failure {
                    Text(verbatim: failure)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.red)
                }
            } header: {
                Text("Ausgewählte Seiten")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fotografiere alle Seiten oder wähle sie in der richtigen Reihenfolge aus. Gut lesbare, gerade Bilder liefern das beste Ergebnis. Beschneide die Bilder so, dass Logos, Kopf- und Fußzeilen möglichst wegfallen.")
                    Text("Bis zu 10 Seiten, in der Reihenfolge der Auswahl.")
                }
            }

            Section {
                Picker("Analyseart", selection: Binding(get: { model.usesCloudAnalysis },
                                                         set: { model.usesCloudAnalysis = $0 })) {
                    Text("Geschützte Cloud-KI").tag(true)
                    Text("Nur auf diesem Gerät").tag(false)
                }
                .pickerStyle(.segmented)
                Text(model.usesCloudAnalysis
                     ? LocalizedStringKey("Die ausgewählten Bilder werden verschlüsselt über den geschützten BackPlaner-Server von Google Vertex AI analysiert. Dafür ist einmalig Deine Einwilligung nötig.")
                     : LocalizedStringKey("Auf Android liest BakePlanner Fotos bisher nur mit der Cloud-KI. Wähle „Geschützte Cloud-KI“, oder lege das Rezept von Hand oder von einer Internetseite an."))
                    .font(AppFont.caption)
            } header: {
                Text("Analyseart")
            }

            if needsConsent {
                // The iPhone's consent before the first cloud analysis. There
                // is no "only locally" here: Android cannot read photos locally.
                Section {
                    Text("Analyse mit Google Vertex AI (Gemini)")
                        .font(AppFont.headline)
                    Text("Die von Dir ausgewählten Rezeptbilder werden verschlüsselt an den geschützten Firebase-Endpunkt von BackPlaner und von dort an Google Vertex AI übertragen. Google ist dabei ein externer KI-Anbieter. Zur Absicherung und Nutzungsbegrenzung werden außerdem eine pseudonyme Firebase-Nutzerkennung, der App-Check-Nachweis sowie Anfragezeit und -anzahl verarbeitet.")
                    Text("Die Bilder werden ausschließlich analysiert, um daraus einen Rezeptentwurf mit Zutaten und Arbeitsschritten zu erstellen. BackPlaner speichert die zur Analyse übertragenen Bilder nicht in Firebase Storage oder in der Rezept-Datenbank.")
                    Button("Zustimmen und mit Cloud-KI analysieren") {
                        model.allowsCloudAnalysis = true
                        Task { await analyze() }
                    }
                    .disabled(pages.isEmpty || isAnalyzing || isPreparing)
                    Text("Du kannst die Einwilligung später unter Einstellungen › Datenschutz & KI widerrufen.")
                        .font(AppFont.caption)
                } header: {
                    Text("Vor der ersten Cloud-Analyse")
                }
            }
        }
        .navigationTitle("Rezept aus Bildern importieren")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Importieren") {
                    Task { await analyze() }
                }
                .disabled(!canImport)
            }
        }
        // The system's file chooser, as for the recipe picture: SkipKit's
        // media picker hands out content:// addresses that native Swift
        // cannot read, the document picker copies the files into the cache.
        .withDocumentPicker(isPresented: $picksPages,
                            allowedContentTypes: [.image],
                            allowsMultipleSelection: true,
                            selectedDocumentURLs: $pickedURLs,
                            selectedFilenames: $pickedNames,
                            selectedFileMimeTypes: $pickedTypes)
        .onChange(of: pickedURLs) { _, urls in
            guard !urls.isEmpty else { return }
            pickedURLs = []
            Task { await append(urls) }
        }
        // A photographed page, taken one at a time.
        .cameraPicker(isPresented: $takesPhoto) { data in
            if pages.count < Self.maximumPages {
                pages.append(ImportPage(data: data))
            }
        }
    }

    /// Adds the picked files as pages, in the order picked, up to the
    /// maximum; files that are no pictures are left out.
    private func append(_ urls: [URL]) async {
        isPreparing = true
        defer { isPreparing = false }
        for url in urls where pages.count < Self.maximumPages {
            if let data = RecipeDetailView.pictureData(at: url) {
                pages.append(ImportPage(data: data))
            }
        }
    }

    private func analyze() async {
        failure = nil
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            var photos: [Data] = []
            for page in pages {
                guard let photo = PhotoShrinker.analysisPhoto(page.data) else {
                    throw RecipeImageAnalysisError.invalidImage
                }
                photos.append(photo)
            }
            let analysis = try await PublicRecipeService.analyzeRecipeImages(photos)
            let recipe = analysis.recipe.makeRecipe()
            guard RecipeImportCheck.hasRecipeData(recipe) else {
                throw RecipeImageAnalysisError.insufficientRecipeData
            }
            // The same last pass as on the iPhone (HybridRecipeImageAnalysisAgent).
            RecipeImportPlan.groupComponentPreparations(in: recipe)
            RecipeImportStepText.applyDefaultDuration(to: recipe.instructions)
            let warnings = analysis.recipe.warnings.joined(separator: "\n")
            let notice: Text? = warnings.isEmpty ? nil : Text(verbatim: warnings)
            logger.info("photo import: cloud AI read \(recipe.components.count) components, \(recipe.instructions.count) steps from \(photos.count) pages")
            onImport(RecipeExportData(recipeFB: recipe, imageData: pages.first?.data), notice)
            dismiss()
        } catch {
            logger.error("photo import failed: \(error)")
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// A page as a small square, so the list shows which pages are chosen.
/// Not private: Skip cannot bridge private views to Android.
struct PageThumbnail: View {
    let data: Data

    var body: some View {
        #if canImport(UIKit) || os(Android)
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 64, height: 64)
    }
}
