import BakePlannerCore
import SwiftUI
import UIKit

/// Imports a recipe from text the person pasted: for pages that render
/// their recipe with JavaScript and so give the web import nothing, and for
/// recipes from messages or notes. The same analysis stages as for a web
/// page's text turn it into a recipe draft.
struct RecipeTextImportView: View {
    @State private var pastedText = ""
    @State private var addressText = ""
    @State private var isAnalyzing = false
    @State private var analysisProgress = "Text wird analysiert …"
    @State private var analysisTask: Task<Void, Never>?
    @State private var analysisResult: RecipeImageAnalysisResult?
    @State private var analyzedURL: URL?
    @State private var errorMessage: String?
    @State private var showRecipeReview = false
    @State private var showCloudConsent = false
    @FocusState private var textFieldFocused: Bool
    @AppStorage(AppSettingsKeys.cloudRecipeAnalysisConsent) private var cloudRecipeAnalysisConsent = false
    @AppStorage(AppSettingsKeys.recipeImageAnalysisMode) private var analysisModeRawValue = RecipeImageAnalysisMode.localOnly.rawValue

    private let analysisAgent = HybridRecipeImageAnalysisAgent()

    var body: some View {
        Group {
            if let analysisResult {
                RecipeImportConfirmationView(
                    result: analysisResult,
                    pageImages: [],
                    sourceURL: analyzedURL,
                    startOverTitle: "Anderen Text einfügen"
                ) {
                    showRecipeReview = true
                } onStartOver: {
                    self.analysisResult = nil
                }
            } else {
                textContent
            }
        }
        .navigationTitle("Rezept aus Text")
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
            CloudRecipeAnalysisConsentView(subject: .text) {
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
    }

    private var textContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ContentUnavailableView(
                    "Eingefügter Rezepttext",
                    systemImage: "text.quote",
                    description: Text("Kopiere den Text eines Rezepts, zum Beispiel von einer Internetseite, die sich nicht laden lässt, und füge ihn hier ein. Die App liest Zutaten und Arbeitsschritte aus und zeigt sie Dir vor dem Speichern.")
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Rezepttext")
                            .font(.headline)
                        Spacer()
                        // The system button reads the clipboard only when
                        // tapped, so no paste prompt appears on arrival.
                        PasteButton(payloadType: String.self) { strings in
                            pastedText = strings.joined(separator: "\n")
                        }
                        .buttonBorderShape(.capsule)
                    }

                    TextEditor(text: $pastedText)
                        .frame(minHeight: 180, maxHeight: 320)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                        .focused($textFieldFocused)
                        .accessibilityLabel("Rezepttext")
                        .overlay(alignment: .topLeading) {
                            if pastedText.isEmpty {
                                Text("Hier den Rezepttext einfügen …")
                                    .foregroundStyle(Theme.subtitle)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                        }

                    if !pastedText.isEmpty, !hasEnoughText {
                        Text("Das ist noch zu wenig Text für ein Rezept.")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Internetadresse (optional)")
                        .font(.headline)
                    TextField("https://…", text: $addressText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Internetadresse der Quelle")
                    Text("Die Adresse wird als Link im Rezept gespeichert.")
                        .font(.footnote)
                        .foregroundStyle(Theme.subtitle)
                    if !addressText.isEmpty, sourceURL == nil {
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

                    Text(analysisMode.explanation(for: .text))
                        .font(.footnote)
                        .foregroundStyle(Theme.subtitle)
                }

                Button {
                    analyzeText()
                } label: {
                    Label("Text analysieren", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAnalyzing || !hasEnoughText)

                Text("Markiere auf der Seite am besten nur das Rezept, von der Überschrift bis zum letzten Arbeitsschritt. Für den privaten Gebrauch ist der Import unbedenklich; veröffentliche fremde Rezepte nur mit Erlaubnis.")
                    .font(.footnote)
                    .foregroundStyle(Theme.subtitle)
            }
            .padding()
        }
        .warmBackground()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { textFieldFocused = false }
            }
        }
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

    private var hasEnoughText: Bool {
        pastedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= PastedRecipeText.minimumCharacters
    }

    /// The source address when one was given and reads like one.
    private var sourceURL: URL? {
        let trimmed = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return RecipeWebPageLoader.normalizedURL(from: trimmed)
    }

    private func analyzeText() {
        textFieldFocused = false
        if analysisMode == .protectedCloud && !cloudRecipeAnalysisConsent {
            showCloudConsent = true
            return
        }
        startAnalysis()
    }

    private func startAnalysis() {
        isAnalyzing = true
        analysisProgress = String(localized: "Text wird analysiert …", bundle: AppSettings.localizationBundle)
        let allowCloud = analysisMode == .protectedCloud
        let text = pastedText
        let url = sourceURL

        analysisTask = Task {
            do {
                let result = try await analysisAgent.analyzeText(text, sourceURL: url, allowCloud: allowCloud) { message in
                    analysisProgress = message
                }
                await MainActor.run {
                    analyzedURL = url
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
