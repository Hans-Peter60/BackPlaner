//
//  DishImportResultSections.swift
//  CookPlanner
//
//  What the text and the web import show once the cloud has answered: the
//  dish found, the analysis' remarks, and the way into the editor.
//

import BakePlannerCore
import SwiftUI

/// The outcome of an import, ready for the editor.
struct DishImportResult {
    var dish: KitchenDish
    var warnings: [String]
    var notice: String?
}

struct DishImportResultSections: View {

    let result: DishImportResult
    /// The cook takes the dish into the editor.
    let onAccept: () -> Void
    /// Back to the input, for another text or address.
    let onRetry: () -> Void
    let retryTitle: LocalizedStringKey

    var body: some View {
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
            Button(action: onAccept) {
                Label("Prüfen und bearbeiten", systemImage: "checkmark.circle")
            }
            Button(retryTitle, action: onRetry)
        } footer: {
            Text("Die Schritte öffnen sich im Editor; gespeichert wird erst mit „Sichern“.")
        }
    }
}
