import PhotosUI
import SwiftUI
import UIKit

private struct SelectedRecipeImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Which reading the import should use. Recognising the template is the app's
/// job, so this only exists to override the choice when the recognition picks
/// the wrong one.
private enum RecipeImportLayout: String, CaseIterable, Identifiable {
    case automatic
    case general
    case ploetzblog

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .automatic: "Automatisch"
        case .general: "Allgemein"
        case .ploetzblog: "Ploetzblog"
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .automatic:
            "Die App liest die Bilder mit jeder bekannten Vorlage und behält das Ergebnis, das zu den Angaben der Seite passt."
        case .general:
            "Für Kochbücher, Zeitschriften, Ausdrucke und andere Rezeptvorlagen."
        case .ploetzblog:
            "Verwendet weiterhin die spezielle Auswertung von Zutaten, Arbeitsschritten und Planungsbeispiel."
        }
    }
}

struct RecipeImageImportView: View {
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [SelectedRecipeImage] = []
    @State private var capturedImage: UIImage?
    @State private var isShowingCamera = false
    @State private var isAnalyzing = false
    @State private var analysisProgress = "OCR wird ausgeführt …"
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisResult: RecipeImageAnalysisResult?
    @State private var errorMessage: String?
    @State private var showRecipeReview = false
    @State private var importLayout = RecipeImportLayout.automatic

    private let analysisAgent = RecipeImageAnalysisAgent()

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

                Picker("Vorlagenart", selection: $importLayout) {
                    ForEach(RecipeImportLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                Text(importLayout.explanation)
                    .font(.footnote)
                    // .secondary is only 2.9:1 on the warm background.
                    .foregroundStyle(Theme.subtitle)

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
        let images = selectedImages.map(\.image)
        guard !images.isEmpty else { return }
        isAnalyzing = true
        analysisProgress = "OCR wird ausgeführt …"

        analysisTask = Task {
            do {
                let progress: @MainActor (Int, Int) -> Void = { current, total in
                    analysisProgress = "Bild \(current) von \(total) wird gelesen …"
                }
                let result: RecipeImageAnalysisResult
                switch importLayout {
                case .automatic:
                    result = try await analysisAgent.analyze(images: images, progress: progress)
                case .general:
                    result = try await analysisAgent.analyzeGeneralRecipe(images: images, progress: progress)
                case .ploetzblog:
                    result = try await analysisAgent.analyzePloetzblogRecipe(images: images, progress: progress)
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
}

private struct RecipeImportConfirmationView: View {
    let result: RecipeImageAnalysisResult
    /// The pages as they were selected, so the name can be corrected by
    /// pointing at the page instead of retyping it.
    let pageImages: [UIImage]
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
                LabeledContent("Erkannte Vorlage") {
                    Text(result.layout.title)
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
                        Text(durationDescription(instruction.duration))
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
                Button("Andere Bilder auswählen", action: onStartOver)
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

    private func durationDescription(_ duration: Int) -> String {
        duration > 0 ? "Dauer: \(duration) Minuten" : "Keine Dauer erkannt"
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
