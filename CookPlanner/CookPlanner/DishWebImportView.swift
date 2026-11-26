//
//  DishWebImportView.swift
//  CookPlanner
//
//  A recipe page from the web, read into work steps: the page is loaded on
//  the device (BakePlannerCore's RecipeWebPageLoader, structured recipe
//  data first, then the readable text), the text goes to the cloud AI, and
//  the dish lands in the editor for the cook to check. Opened from the "+"
//  menu with an empty field, or with an address from the share extension
//  (analysis starts at once) or from any link to the app (the cook taps).
//

import BakePlannerCore
import SwiftUI
import UIKit

struct DishWebImportView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var addressText: String
    @State private var isAnalyzing = false
    @State private var progress: LocalizedStringKey = "Seite wird geladen …"
    @State private var errorMessage: String?
    /// The monthly allowance is used up: the alert offers Pro.
    @State private var limitReached = false
    @State private var showingPro = false
    @State private var result: DishImportResult?
    @State private var analysisTask: Task<Void, Never>?
    @FocusState private var editing: Bool
    /// Called with the dish the cook accepted for the editor.
    let onImported: (KitchenDish) -> Void
    private let startsAutomatically: Bool

    /// `address` pre-fills the field; with `startsAutomatically` the
    /// analysis begins without a tap — only for the share extension, so
    /// that no link from outside can spend a cloud import unasked.
    init(address: URL? = nil, startsAutomatically: Bool = false, onImported: @escaping (KitchenDish) -> Void) {
        _addressText = State(initialValue: address?.absoluteString ?? "")
        self.startsAutomatically = startsAutomatically && address != nil
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    DishImportResultSections(result: result, onAccept: {
                        onImported(result.dish)
                        dismiss()
                    }, onRetry: {
                        self.result = nil
                    }, retryTitle: "Andere Seite analysieren")
                } else {
                    inputSections
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Aus Webseite importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        analysisTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { editing = false }
                }
            }
            .alert("Import fehlgeschlagen",
                   isPresented: Binding(get: { errorMessage != nil },
                                        set: { if !$0 { errorMessage = nil; limitReached = false } })) {
                if limitReached && !CookPro.shared.hasPurchased {
                    Button("Pro freischalten") { showingPro = true }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingPro) {
                CookProPaywallView()
            }
            .task {
                if startsAutomatically && normalizedURL != nil && !isAnalyzing && result == nil {
                    analyze()
                }
            }
        }
        .interactiveDismissDisabled(isAnalyzing)
    }

    @ViewBuilder
    private var inputSections: some View {
        Section {
            TextField("https://…", text: $addressText)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($editing)
                .submitLabel(.go)
                .onSubmit { analyze() }
            PasteButton(payloadType: String.self) { strings in
                if let pasted = strings.first { addressText = pasted }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
        } header: {
            Text("Adresse der Rezeptseite")
        } footer: {
            Text("Die Seite wird auf diesem Gerät geladen; nur der Rezepttext geht zur Analyse an einen Dienst von Google.")
        }
        Section {
            Button {
                analyze()
            } label: {
                if isAnalyzing {
                    HStack {
                        ProgressView()
                        Text(progress)
                    }
                } else {
                    Label("Analysieren", systemImage: "sparkles")
                }
            }
            .disabled(isAnalyzing || normalizedURL == nil)
        }
    }

    private var normalizedURL: URL? {
        RecipeWebPageLoader.normalizedURL(from: addressText)
    }

    private func analyze() {
        guard let url = normalizedURL, !isAnalyzing else { return }
        editing = false
        isAnalyzing = true
        progress = "Seite wird geladen …"
        analysisTask = Task {
            defer {
                isAnalyzing = false
                analysisTask = nil
            }
            do {
                let page = try await RecipeWebPageLoader.load(url)
                try Task.checkCancellation()
                progress = "Wird analysiert …"
                let analysis = try await DishImportClient.shared.analyzeText(page.analysisText)
                try Task.checkCancellation()
                let dish = CloudDishImport.dish(from: analysis.dish, source: .web,
                                                fallbackName: page.title.isEmpty ? String(localized: "Gericht") : page.title)
                result = DishImportResult(dish: dish, warnings: analysis.dish.warnings ?? [],
                                          notice: analysis.freeImports?.cookNotice)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                if case DishImportError.monthlyLimit = error { limitReached = true }
            }
        }
    }
}
