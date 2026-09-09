//
//  TabsFBView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 08.12.21.
//

import SwiftUI
import CoreData
import Translation

struct TabsFBView: View {

    @State private var tabSelection = 0

    var recipeFB:RecipeFB

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var modelFB: RecipeFBModel
    @ObservedObject private var moderation = ModerationStore.shared

    // Moderation UI state (App Store Guideline 1.2: users must be able to
    // flag content and block abusive authors; deleting own content is recommended).
    @State private var showReportDialog = false
    @State private var showDeleteConfirm = false
    // Error message shown when deleting the own recipe fails, so the screen no
    // longer silently dismisses (leaving the recipe in the list) as if it worked.
    @State private var deleteErrorMessage: String?

    // Translation state: switching language re-writes the shared recipeFB, so both tabs update.
    @State private var selectedLanguage = ""
    @State private var pendingLanguage: String?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false
    @State private var translationError: String?

    /// True when this public recipe was uploaded from this device, so the author
    /// may delete it. Empty author ids (legacy recipes) never match.
    private var isOwnRecipe: Bool {
        guard let author = recipeFB.authorId, !author.isEmpty else { return false }
        return author == moderation.authorId
    }

    var body: some View {
        TabView (selection: $modelFB.tabSelection) {

            InstructionsFBView(recipeFB: recipeFB, languageCode: selectedLanguage)
                .tabItem {
                    VStack {
                        Image(systemName: "dial.max.fill")
                        Text("Rezept backen")
                    }
                }
                .tag(0)

             RecipeFBDetailView(recipeFB: recipeFB)
                .tabItem {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Details")
                    }
                }
                .tag(1)
        }
        // accentText, not accentBottom: the tab bar keeps the system's own
        // background, so the tint has to be light in dark mode, not dark.
        .tint(Theme.accentText)
        .task {
            // Load this recipe's components and steps on demand, so both the
            // baking and the details tab work even when the global "Detailansicht"
            // prefetch (Settings → Detailansicht verwenden) is off, or hasn't
            // finished yet. Guarded on empty to avoid duplicate rows.
            if recipeFB.components.isEmpty {
                modelFB.getComponentsFB(recipeFB, recipeFB.id ?? "")
            }
            if recipeFB.instructions.isEmpty {
                modelFB.getInstructionsFB(recipeFB, recipeFB.id ?? "")
            }
            // Re-evaluate admin status here too, in case the anonymous sign-in or
            // the admins document became available after launch.
            modelFB.checkAdminStatus()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(RecipeTranslator.supportedLanguages) { language in
                        Button {
                            select(language.code)
                        } label: {
                            if selectedLanguage == language.code {
                                Label(language.name, systemImage: "checkmark")
                            } else {
                                Text(language.name)
                            }
                        }
                    }
                } label: {
                    if isTranslating {
                        ProgressView()
                    } else {
                        Image(systemName: "globe")
                    }
                }
                .disabled(isTranslating)
                .accessibilityLabel(isTranslating ? "Übersetzt …" : "Sprache wählen")
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showReportDialog = true
                    } label: {
                        Label("Rezept melden", systemImage: "flag")
                    }

                    Button(role: .destructive) {
                        moderation.block(author: recipeFB.authorId)
                        dismiss()
                    } label: {
                        Label("Autor blockieren", systemImage: "hand.raised")
                    }

                    if isOwnRecipe {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Mein Rezept löschen", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Weitere Aktionen")
            }
        }
        .confirmationDialog("Rezept melden", isPresented: $showReportDialog, titleVisibility: .visible) {
            ForEach(reportReasons, id: \.self) { reason in
                Button(reason, role: .destructive) {
                    report(reason: reason)
                }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Warum meldest Du dieses Rezept? Es wird sofort für alle Nutzer ausgeblendet und anschließend geprüft.")
        }
        .confirmationDialog("Mein Rezept löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                modelFB.deleteOwnRecipe(recipeFB) { result in
                    switch result {
                    case .success:
                        dismiss()
                    case .failure(let error):
                        deleteErrorMessage = error.localizedDescription
                    }
                }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text(recipeFB.visibility == .authorOnly
                 ? "Das Rezept wird endgültig aus Deiner privaten Ablage in der Rezept-Datenbank entfernt."
                 : "Das Rezept wird endgültig aus der öffentlichen Datenbank entfernt.")
        }
        .alert("Löschen fehlgeschlagen",
               isPresented: Binding(get: { deleteErrorMessage != nil },
                                    set: { if !$0 { deleteErrorMessage = nil } })) {
            Button("OK", role: .cancel) { deleteErrorMessage = nil }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .translationTask(translationConfig) { session in
            guard let target = pendingLanguage else { return }
            let from = selectedLanguage
            isTranslating = true
            do {
                try await RecipeTranslator.translate(recipeFB, from: from, into: target, using: session)
                selectedLanguage = target
                modelFB.saveTranslations(recipeFB)
            } catch {
                translationError = error.localizedDescription
            }
            isTranslating = false
            pendingLanguage = nil
        }
        .alert("Übersetzung fehlgeschlagen",
               isPresented: Binding(get: { translationError != nil },
                                    set: { if !$0 { translationError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(translationError ?? "")
        }
        .onAppear {
            if selectedLanguage.isEmpty {
                selectedLanguage = RecipeTranslator.showCachedIfAvailable(recipeFB, languageCode: RecipeFB.preferredLanguageCode)
                    ? RecipeFB.preferredLanguageCode
                    : RecipeTranslator.sourceLanguageCode(for: recipeFB)
            }
        }
    }

    /// Switches the displayed language for the shared recipe, translating on-device when needed.
    private func select(_ code: String) {
        guard code != selectedLanguage, !isTranslating else { return }

        if RecipeTranslator.showCachedIfAvailable(recipeFB, languageCode: code) {
            selectedLanguage = code
            return
        }

        // Not cached yet: kick off an on-device translation via the translationTask above.
        pendingLanguage = code
        let source = RecipeTranslator.sourceLanguageCode(for: recipeFB)
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: code)
        )
    }

    /// Reasons offered when reporting a public recipe.
    private var reportReasons: [String] {
        ["Anstößig oder beleidigend", "Spam", "Urheberrechtsverletzung", "Sonstiges"]
    }

    /// Files the report — which withholds the recipe from every user server-side —
    /// hides it locally as well in case that write fails offline, and returns to
    /// the list.
    private func report(reason: String) {
        modelFB.reportRecipe(recipeFB, reason: reason)
        moderation.hide(recipeId: recipeFB.id)
        dismiss()
    }
}
