import SwiftUI
import UIKit

/// Imports a recipe from a web page: the page is loaded on the device, its
/// structured data and text are extracted, and the same analysis stages as
/// for photographed pages turn them into a recipe draft.
struct RecipeWebImportView: View {
    @State private var addressText: String
    /// True until the address the share extension handed over has been
    /// analysed once; afterwards the view behaves like the typed-in case.
    @State private var startsAutomatically: Bool
    @State private var isAnalyzing = false
    @State private var analysisProgress = "Seite wird geladen …"
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisResult: RecipeImageAnalysisResult?
    @State private var analyzedURL: URL?
    @State private var errorMessage: String?
    @State private var showRecipeReview = false
    @State private var showCloudConsent = false
    @FocusState private var addressFieldFocused: Bool
    @AppStorage(AppSettingsKeys.cloudRecipeAnalysisConsent) private var cloudRecipeAnalysisConsent = false
    @AppStorage(AppSettingsKeys.recipeImageAnalysisMode) private var analysisModeRawValue = RecipeImageAnalysisMode.localOnly.rawValue

    private let analysisAgent = HybridRecipeImageAnalysisAgent()

    /// With `initialURL` — the page shared from Safari — the analysis starts
    /// on its own; without it the view waits for an address to be typed.
    init(initialURL: URL? = nil) {
        _addressText = State(initialValue: initialURL?.absoluteString ?? "")
        _startsAutomatically = State(initialValue: initialURL != nil)
    }

    var body: some View {
        Group {
            if let analysisResult {
                RecipeImportConfirmationView(
                    result: analysisResult,
                    pageImages: [],
                    sourceURL: analyzedURL,
                    startOverTitle: "Andere Seite laden"
                ) {
                    showRecipeReview = true
                } onStartOver: {
                    self.analysisResult = nil
                }
            } else {
                addressContent
            }
        }
        .navigationTitle("Rezept von einer Internetseite")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showRecipeReview) {
            if let analysisResult {
                AddNewRecipeDataView(
                    recipe: analysisResult.recipe,
                    recipeImage: analysisResult.recipeImage
                )
            }
        }
        .sheet(isPresented: $showCloudConsent) {
            CloudRecipeAnalysisConsentView(subject: .webPage) {
                cloudRecipeAnalysisConsent = true
                showCloudConsent = false
                startAnalysis()
            } onUseLocal: {
                analysisMode = .localOnly
                showCloudConsent = false
                startAnalysis()
            }
        }
        .alert("Import nicht möglich", isPresented: Binding(
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
        .onAppear {
            guard startsAutomatically else { return }
            startsAutomatically = false
            analyzeAddress()
        }
    }

    private var addressContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ContentUnavailableView(
                    "Adresse der Rezeptseite",
                    systemImage: "globe",
                    description: Text("Füge die Adresse einer Internetseite mit einem Backrezept ein. Die App lädt die Seite, liest Zutaten und Arbeitsschritte aus und zeigt sie Dir vor dem Speichern.")
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Internetadresse")
                        .font(.headline)

                    HStack(spacing: 12) {
                        TextField("https://…", text: $addressText)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($addressFieldFocused)
                            .onSubmit(analyzeAddress)
                            .padding(10)
                            .background(.background, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityLabel("Internetadresse der Rezeptseite")

                        // The system button reads the clipboard only when
                        // tapped, so no paste prompt appears on arrival.
                        PasteButton(payloadType: String.self) { strings in
                            guard let pasted = strings.first else { return }
                            addressText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                    }

                    if !addressText.isEmpty, normalizedURL == nil {
                        Text("Das sieht noch nicht nach einer vollständigen Internetadresse aus.")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
                .cardStyle()

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

                    Text(analysisMode.explanation(for: .webPage))
                        .font(.footnote)
                        .foregroundStyle(Theme.subtitle)
                }

                Button {
                    analyzeAddress()
                } label: {
                    Label("Seite laden und analysieren", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing || normalizedURL == nil)

                Text("Seiten mit Anmeldung, Bezahlschranke oder Cookie-Hinweis lassen sich oft nicht auslesen. Für den privaten Gebrauch ist der Import unbedenklich; veröffentliche fremde Rezepte nur mit Erlaubnis.")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtitle)
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
    }

    private var normalizedURL: URL? {
        RecipeWebPageLoader.normalizedURL(from: addressText)
    }

    private func analyzeAddress() {
        guard normalizedURL != nil else {
            errorMessage = RecipeWebImportError.invalidAddress.localizedDescription
            return
        }
        addressFieldFocused = false
        if analysisMode == .protectedCloud && !cloudRecipeAnalysisConsent {
            showCloudConsent = true
            return
        }
        startAnalysis()
    }

    private func startAnalysis() {
        guard let url = normalizedURL else { return }
        isAnalyzing = true
        analysisProgress = String(localized: "Seite wird geladen …", bundle: AppSettings.localizationBundle)
        let allowCloud = analysisMode == .protectedCloud

        analysisTask = Task {
            do {
                let page = try await RecipeWebPageLoader.load(url)
                try Task.checkCancellation()
                let result = try await analysisAgent.analyzeWebPage(page, allowCloud: allowCloud) { message in
                    analysisProgress = message
                }
                await MainActor.run {
                    analyzedURL = page.url
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
