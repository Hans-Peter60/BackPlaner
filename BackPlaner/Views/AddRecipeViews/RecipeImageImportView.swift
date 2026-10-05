import PhotosUI
import SwiftUI
import UIKit

private struct SelectedRecipeImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// What the cloud analysis would receive: the photographed pages, or the
/// text of a recipe web page. The consent and the explanations name it.
enum CloudAnalysisSubject {
    case images
    case webPage
}

/// Shared by the image and the web import; the choice is persisted once.
enum RecipeImageAnalysisMode: String, CaseIterable, Identifiable {
    case protectedCloud
    case localOnly

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .protectedCloud: "Geschützte Cloud-KI"
        case .localOnly: "Nur auf diesem Gerät"
        }
    }

    func explanation(for subject: CloudAnalysisSubject) -> LocalizedStringResource {
        switch (self, subject) {
        case (.protectedCloud, .images):
            "Die ausgewählten Bilder werden verschlüsselt über den geschützten BackPlaner-Server von Google Vertex AI analysiert. Dafür ist einmalig Deine Einwilligung nötig."
        case (.protectedCloud, .webPage):
            "Der Rezepttext der Seite wird verschlüsselt über den geschützten BackPlaner-Server von Google Vertex AI analysiert. Dafür ist einmalig Deine Einwilligung nötig."
        case (.localOnly, .images):
            "Die Bilder verlassen das Gerät nicht. Die Erkennung kann weniger genau sein als mit der Cloud-KI."
        case (.localOnly, .webPage):
            "Der Seitentext verlässt das Gerät nicht. Ohne Apple Intelligence werden nur die strukturierten Rezeptdaten der Seite übernommen."
        }
    }
}

struct RecipeImageImportView: View {
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [SelectedRecipeImage] = []
    @State private var capturedImage: UIImage?
    @State private var isShowingCamera = false
    @State private var isAnalyzing = false
    @State private var analysisProgress = "Rezept wird analysiert …"
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisResult: RecipeImageAnalysisResult?
    @State private var errorMessage: String?
    @State private var showRecipeReview = false
    @State private var showCloudConsent = false
    @AppStorage(AppSettingsKeys.cloudRecipeAnalysisConsent) private var cloudRecipeAnalysisConsent = false
    @AppStorage(AppSettingsKeys.recipeImageAnalysisMode) private var analysisModeRawValue = RecipeImageAnalysisMode.localOnly.rawValue

    private let analysisAgent = HybridRecipeImageAnalysisAgent()

    var body: some View {
        Group {
            if let analysisResult {
                RecipeImportConfirmationView(
                    result: analysisResult,
                    pageImages: selectedImages.map(\.image)
                ) {
                    showRecipeReview = true
                } onStartOver: {
                    self.analysisResult = nil
                }
            } else {
                imageSelectionContent
            }
        }
        .navigationTitle("Rezept aus Bildern")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showRecipeReview) {
            if let analysisResult {
                AddNewRecipeDataView(
                    recipe: analysisResult.recipe,
                    recipeImage: analysisResult.recipeImage
                        ?? selectedImages.first?.image
                )
            }
        }
        .sheet(isPresented: $isShowingCamera, onDismiss: appendCapturedImage) {
            ImagePicker(selectedSource: .camera, recipeImage: $capturedImage)
        }
        .sheet(isPresented: $showCloudConsent) {
            CloudRecipeAnalysisConsentView(subject: .images) {
                cloudRecipeAnalysisConsent = true
                showCloudConsent = false
                startAnalysis()
            } onUseLocal: {
                analysisMode = .localOnly
                showCloudConsent = false
                startAnalysis()
            }
        }
        .alert("Analyse nicht möglich", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            analysisTask?.cancel()
        }
    }

    private var imageSelectionContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ContentUnavailableView(
                    "Rezeptbilder auswählen",
                    systemImage: "doc.viewfinder",
                    description: Text("Fotografiere alle Seiten oder wähle sie in der richtigen Reihenfolge aus. Gut lesbare, gerade Bilder liefern das beste Ergebnis. Beschneide die Bilder so, dass Logos, Kopf- und Fußzeilen möglichst wegfallen.")
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Analyseart")
                        .font(.headline)

                    Picker("Analyseart", selection: analysisModeBinding) {
                        ForEach(RecipeImageAnalysisMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(analysisMode.explanation(for: .images))
                        .font(.footnote)
                        .foregroundStyle(Theme.subtitle)
                }

                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 10,
                        selectionBehavior: .ordered,
                        matching: .images
                    ) {
                        Label("Bilder auswählen", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            isShowingCamera = true
                        } label: {
                            Label("Aufnehmen", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if !selectedImages.isEmpty {
                    selectedImageList

                    Button {
                        analyzeImages()
                    } label: {
                        Label("\(selectedImages.count) Bild(er) analysieren", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing)
                }
            }
            .padding()
        }
        .warmBackground()
        .overlay {
            if isAnalyzing {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(analysisProgress)
                    Button("Abbrechen", role: .cancel) {
                        cancelAnalysis()
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task { await loadPhotoItems(newItems) }
        }
    }

    private var selectedImageList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ausgewählte Seiten")
                .font(.headline)

            ForEach(Array(selectedImages.enumerated()), id: \.element.id) { index, selectedImage in
                HStack(spacing: 12) {
                    Image(uiImage: selectedImage.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Rezeptseite \(index + 1)")

                    Text("Seite \(index + 1)")
                    Spacer()
                    Button(role: .destructive) {
                        selectedImages.removeAll { $0.id == selectedImage.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Seite \(index + 1) entfernen")
                }
            }
        }
        .cardStyle()
    }

    @MainActor
    private func loadPhotoItems(_ items: [PhotosPickerItem]) async {
        var loadedImages: [SelectedRecipeImage] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { continue }
            loadedImages.append(SelectedRecipeImage(image: image))
        }
        selectedImages = loadedImages
    }

    private func appendCapturedImage() {
        guard let capturedImage else { return }
        selectedImages.append(SelectedRecipeImage(image: capturedImage))
        self.capturedImage = nil
    }

    private func analyzeImages() {
        guard !selectedImages.isEmpty else { return }
        if analysisMode == .protectedCloud && !cloudRecipeAnalysisConsent {
            showCloudConsent = true
            return
        }
        startAnalysis()
    }

    private func startAnalysis() {
        let images = selectedImages.map(\.image)
        guard !images.isEmpty else { return }
        isAnalyzing = true
        analysisProgress = "Rezept wird analysiert …"

        analysisTask = Task {
            do {
                let progress: @MainActor (Int, Int) -> Void = { current, total in
                    analysisProgress = "Bild \(current) von \(total) wird gelesen …"
                }
                // The template (general vs. special) is always recognised
                // automatically; the local agent tries every known reading.
                let result: RecipeImageAnalysisResult
                switch analysisMode {
                case .protectedCloud:
                    result = try await analysisAgent.analyze(images: images, progress: progress)
                case .localOnly:
                    result = try await analysisAgent.analyzeLocally(images: images, progress: progress)
                }
                await MainActor.run {
                    analysisResult = result
                    isAnalyzing = false
                    analysisTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    isAnalyzing = false
                    analysisTask = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAnalyzing = false
                    analysisTask = nil
                }
            }
        }
    }

    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }

    private var analysisMode: RecipeImageAnalysisMode {
        get { RecipeImageAnalysisMode(rawValue: analysisModeRawValue) ?? .localOnly }
        nonmutating set { analysisModeRawValue = newValue.rawValue }
    }

    private var analysisModeBinding: Binding<RecipeImageAnalysisMode> {
        Binding(
            get: { analysisMode },
            set: { analysisMode = $0 }
        )
    }
}

struct CloudRecipeAnalysisConsentView: View {
    @Environment(\.dismiss) private var dismiss

    let subject: CloudAnalysisSubject
    let onAccept: () -> Void
    let onUseLocal: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Analyse mit Google Vertex AI (Gemini)", systemImage: "sparkles")
                        .font(.headline)
                    switch subject {
                    case .images:
                        Text("Die von Dir ausgewählten Rezeptbilder werden verschlüsselt an den geschützten Firebase-Endpunkt von BackPlaner und von dort an Google Vertex AI übertragen. Google ist dabei ein externer KI-Anbieter. Zur Absicherung und Nutzungsbegrenzung werden außerdem eine pseudonyme Firebase-Nutzerkennung, der App-Check-Nachweis sowie Anfragezeit und -anzahl verarbeitet.")
                        Text("Die Bilder werden ausschließlich analysiert, um daraus einen Rezeptentwurf mit Zutaten und Arbeitsschritten zu erstellen. BackPlaner speichert die zur Analyse übertragenen Bilder nicht in Firebase Storage oder in der Rezept-Datenbank.")
                    case .webPage:
                        Text("Der Rezepttext der von Dir angegebenen Internetseite und ihre Adresse werden verschlüsselt an den geschützten Firebase-Endpunkt von BackPlaner und von dort an Google Vertex AI übertragen. Google ist dabei ein externer KI-Anbieter. Zur Absicherung und Nutzungsbegrenzung werden außerdem eine pseudonyme Firebase-Nutzerkennung, der App-Check-Nachweis sowie Anfragezeit und -anzahl verarbeitet.")
                        Text("Die Seite selbst wird von Deinem Gerät geladen. Der Text wird ausschließlich analysiert, um daraus einen Rezeptentwurf mit Zutaten und Arbeitsschritten zu erstellen. BackPlaner speichert den übertragenen Text nicht in Firebase Storage oder in der Rezept-Datenbank.")
                    }
                } header: {
                    Text("Vor der ersten Cloud-Analyse")
                }

                Section("Du hast die Wahl") {
                    switch subject {
                    case .images:
                        Text("Du kannst stattdessen jederzeit die lokale Analyse verwenden. Dann verlassen die Bilder Dein Gerät nicht.")
                    case .webPage:
                        Text("Du kannst stattdessen jederzeit die lokale Analyse verwenden. Dann verlässt der Seitentext Dein Gerät nicht.")
                    }

                    Button("Zustimmen und mit Cloud-KI analysieren") {
                        onAccept()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Nur lokal analysieren") {
                        onUseLocal()
                    }
                }

                Section {
                    Text("Du kannst die Einwilligung später unter Einstellungen › Datenschutz & KI widerrufen.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Cloud-KI erlauben?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

struct RecipeImportConfirmationView: View {
    let result: RecipeImageAnalysisResult
    /// The pages as they were selected, so the name can be corrected by
    /// pointing at the page instead of retyping it.
    let pageImages: [UIImage]
    /// The web page the recipe came from; shown instead of the page layout.
    var sourceURL: URL? = nil
    var startOverTitle: LocalizedStringResource = "Andere Bilder auswählen"
    let onConfirm: () -> Void
    let onStartOver: () -> Void

    @State private var isChoosingTitle = false
    /// Mirrors the recipe's name so the row refreshes after a correction:
    /// RecipeFB is observable, but the name is read once while the list builds.
    @State private var recipeName = ""

    /// Whether the name can be corrected by pointing at a page.
    private var canPickTitle: Bool {
        !pageImages.isEmpty && result.titleOptions.contains { pageImages.indices.contains($0.page) }
    }

    var body: some View {
        List {
            Section("Erkanntes Rezept") {
                if canPickTitle {
                    Button {
                        isChoosingTitle = true
                    } label: {
                        LabeledContent("Name") {
                            HStack(spacing: 6) {
                                Text(recipeName)
                                Image(systemName: "square.dashed.inset.filled")
                            }
                        }
                    }
                    .tint(Theme.accentText)
                    .accessibilityLabel("Name: \(recipeName)")
                    .accessibilityHint("Namen auf der Seite auswählen")
                    .sheet(isPresented: $isChoosingTitle) {
                        RecipeTitleRegionPickerView(
                            pageImages: pageImages,
                            regions: result.titleOptions,
                            currentTitle: recipeName
                        ) { chosen in
                            result.recipe.name = chosen
                            recipeName = chosen
                        }
                    }
                } else {
                    LabeledContent("Name", value: recipeName)
                }
                if let sourceURL {
                    LabeledContent("Quelle", value: sourceURL.host() ?? sourceURL.absoluteString)
                } else {
                    LabeledContent("Erkannte Vorlage") {
                        Text(result.layout.title)
                    }
                }
                LabeledContent("Analyse") {
                    Text(result.analysisSource.title)
                }
                LabeledContent("Komponenten", value: result.componentCount.formatted())
                LabeledContent("Zutaten", value: result.ingredientCount.formatted())
                LabeledContent("Arbeitsschritte", value: result.instructionCount.formatted())
            }

            Section("Komponenten und Zutaten") {
                ForEach(result.recipe.components) { component in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(component.name).font(.headline)
                        ForEach(component.ingredients) { ingredient in
                            Text(ingredientDescription(ingredient))
                                .foregroundStyle(Theme.subtitle)
                        }
                    }
                }
            }

            Section("Erkannte Zeitplanung") {
                ForEach(result.recipe.instructions) { instruction in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(instruction.instruction)
                        // The step number shows whether the preparations were
                        // laid out in parallel (1.1, 1.2 …) before anything is saved.
                        Text("\(stepDescription(instruction.step)) · \(durationDescription(instruction.duration))")
                            .font(.caption)
                            .foregroundStyle(Theme.subtitle)
                    }
                }
            }

            if !result.warnings.isEmpty {
                Section("Bitte besonders prüfen") {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            // This is warning TEXT, not just an icon: system
                            // .orange is 2.2:1 on white, well under the 4.5 needed.
                            .foregroundStyle(Theme.warning)
                    }
                }
            }

            Section("Hinweis") {
                Text("Bitte prüfe Mengen, Einheiten, Temperaturen und Zeiten im nächsten Schritt. Das Rezept wird erst gespeichert, wenn du dort „Rezept speichern“ auswählst.")
                if canPickTitle {
                    Text("Stimmt der Name nicht, tippe ihn oben an — dann kannst du die richtige Zeile direkt auf der Seite auswählen.")
                }
            }

            Section {
                Button("Daten im Rezeptformular prüfen", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                Button(startOverTitle, action: onStartOver)
            }
        }
        .onAppear {
            if recipeName.isEmpty { recipeName = result.recipe.name }
        }
    }

    private func ingredientDescription(_ ingredient: IngredientFB) -> String {
        let amount = ingredient.weight.formatted(.number.precision(.fractionLength(0...2)))
        return [amount, ingredient.unit, ingredient.name]
            .filter { !$0.isEmpty && $0 != "0" }
            .joined(separator: " ")
    }

    // Plain string literals in a String-returning function never reach the
    // catalog, so these went out in German whatever the app language; they
    // resolve through the app's bundle like the other in-app texts.
    private func stepDescription(_ step: Double) -> String {
        let number = step.formatted(.number.precision(.fractionLength(0...2)))
        return String(localized: "Schritt \(number)", bundle: AppSettings.localizationBundle)
    }

    private func durationDescription(_ duration: Int) -> String {
        let bundle = AppSettings.localizationBundle
        switch duration {
        case ..<1: return String(localized: "Keine Dauer erkannt", bundle: bundle)
        case 1: return String(localized: "Dauer: 1 Minute", bundle: bundle)
        case ..<60: return String(localized: "Dauer: \(duration) Minuten", bundle: bundle)
        default:
            return duration % 60 == 0
                ? String(localized: "Dauer: \(duration / 60) Std.", bundle: bundle)
                : String(localized: "Dauer: \(duration / 60) Std. \(duration % 60) Min.", bundle: bundle)
        }
    }
}

struct AddNewRecipeDataView: View {
    let recipe: RecipeFB?
    let recipeImage: UIImage?

    init(recipe: RecipeFB? = nil, recipeImage: UIImage? = nil) {
        self.recipe = recipe
        self.recipeImage = recipeImage
    }

    var body: some View {
        AddRecipeView(initialRecipe: recipe, initialImage: recipeImage)
    }
}
