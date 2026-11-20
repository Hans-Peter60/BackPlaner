//
//  DishTextImportView.swift
//  CookPlanner
//
//  A recipe pasted as text, read into work steps by the cloud AI, and
//  handed to the editor for the cook to check before it is kept.
//

import BakePlannerCore
import SwiftUI
import UIKit

struct DishTextImportView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var result: (dish: KitchenDish, warnings: [String], notice: String?)?
    @FocusState private var editing: Bool
    /// Called with the dish the cook accepted for the editor.
    let onImported: (KitchenDish) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    resultSections(result)
                } else {
                    inputSections
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Aus Text importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isAnalyzing)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { editing = false }
                }
            }
            .alert("Import fehlgeschlagen",
                   isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isAnalyzing)
        #if DEBUG
        // Development builds take the text from a file named by the launch
        // argument -ImportTextFile, for import runs on the simulator where
        // the paste button cannot be driven.
        .onAppear {
            guard text.isEmpty, let path = UserDefaults.standard.string(forKey: "ImportTextFile"),
                  let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            text = contents
        }
        #endif
    }

    @ViewBuilder
    private var inputSections: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .focused($editing)
            // The system's paste button: no permission prompt, the text
            // arrives only when the person taps it.
            PasteButton(payloadType: String.self) { strings in
                if let pasted = strings.first { text = pasted }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
        } header: {
            Text("Rezepttext")
        } footer: {
            Text("Zutaten und Zubereitung, wie sie im Rezept stehen. Die Analyse schätzt die Arbeitszeiten und schlägt Reihenfolge und Abhängigkeiten vor; Du prüfst alles, bevor es gespeichert wird.")
        }
        Section {
            Button {
                analyze()
            } label: {
                if isAnalyzing {
                    HStack {
                        ProgressView()
                        Text("Wird analysiert …")
                    }
                } else {
                    Label("Analysieren", systemImage: "sparkles")
                }
            }
            .disabled(isAnalyzing || text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40)
        } footer: {
            Text("Der Text wird zur Analyse an einen Dienst von Google gesendet.")
        }
    }

    @ViewBuilder
    private func resultSections(_ result: (dish: KitchenDish, warnings: [String], notice: String?)) -> some View {
        Section("Gefunden") {
            Text(verbatim: result.dish.name)
                .font(.headline)
            Text("\(result.dish.tasks.count) Schritte, \(result.dish.components.count) Komponenten")
            if let servings = result.dish.servings {
                Text("Für \(servings) Personen")
            }
            if let notice = result.notice {
                Text(verbatim: notice)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        if !result.warnings.isEmpty {
            Section("Hinweise der Analyse") {
                ForEach(result.warnings, id: \.self) { warning in
                    Text(verbatim: warning)
                        .font(.footnote)
                }
            }
        }
        Section {
            Button {
                onImported(result.dish)
                dismiss()
            } label: {
                Label("Prüfen und bearbeiten", systemImage: "checkmark.circle")
            }
            Button("Anderen Text analysieren") {
                self.result = nil
            }
        } footer: {
            Text("Die Schritte öffnen sich im Editor; gespeichert wird erst mit „Sichern“.")
        }
    }

    private func analyze() {
        editing = false
        isAnalyzing = true
        let input = text
        Task {
            defer { isAnalyzing = false }
            do {
                let analysis = try await DishImportClient.shared.analyzeText(input)
                let dish = CloudDishImport.dish(from: analysis.dish, source: .text,
                                                fallbackName: String(localized: "Gericht"))
                result = (dish, analysis.dish.warnings ?? [], analysis.freeImports?.notice())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
