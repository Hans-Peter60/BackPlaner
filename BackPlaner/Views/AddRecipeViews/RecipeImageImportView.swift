import PhotosUI
import SwiftUI
import UIKit

private struct SelectedRecipeImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum RecipeImportLayout: String, CaseIterable, Identifiable {
    case general
    case ploetzblog

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "Allgemeine Rezeptvorlage"
        case .ploetzblog: "Ploetzblog (zweispaltig)"
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
    @State private var importLayout = RecipeImportLayout.general

    private let analysisAgent = RecipeImageAnalysisAgent()

    var body: some View {
        Group {
            if let analysisResult {
                RecipeImportConfirmationView(result: analysisResult) {
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
                    description: Text("Fotografiere alle Seiten oder wähle sie in der richtigen Reihenfolge aus. Gut lesbare, gerade Bilder liefern das beste Ergebnis.")
                )

                Picker("Vorlagenart", selection: $importLayout) {
                    ForEach(RecipeImportLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                Text(importLayout == .general
                     ? "Für Kochbücher, Zeitschriften, Ausdrucke und andere Rezeptvorlagen."
                     : "Verwendet weiterhin die spezielle Auswertung von Zutaten, Arbeitsschritten und Planungsbeispiel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
                let result: RecipeImageAnalysisResult
                switch importLayout {
                case .general:
                    result = try await analysisAgent.analyzeGeneralRecipe(images: images) { current, total in
                        analysisProgress = "Bild \(current) von \(total) wird gelesen …"
                    }
                case .ploetzblog:
                    result = try await analysisAgent.analyze(images: images) { current, total in
                        analysisProgress = "Bild \(current) von \(total) wird gelesen …"
                    }
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
    let onConfirm: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        List {
            Section("Erkanntes Rezept") {
                LabeledContent("Name", value: result.recipe.name)
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
                                .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !result.warnings.isEmpty {
                Section("Bitte besonders prüfen") {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Hinweis") {
                Text("Bitte prüfe Mengen, Einheiten, Temperaturen und Zeiten im nächsten Schritt. Das Rezept wird erst gespeichert, wenn du dort „Rezept speichern“ auswählst.")
            }

            Section {
                Button("Daten im Rezeptformular prüfen", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                Button("Andere Bilder auswählen", action: onStartOver)
            }
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
