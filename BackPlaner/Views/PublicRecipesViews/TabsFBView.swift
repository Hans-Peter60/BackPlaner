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

    /// Tags of the tabs.
    private static let bakingTab = 0
    private static let detailsTab = 1

    /// A recipe opens on its details. The baking tab works out the plan, so
    /// it is built only once it is chosen, and then kept.
    @State private var tabSelection = TabsFBView.detailsTab
    @State private var bakingTabOpened = false

    var recipeFB:RecipeFB

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var modelFB: RecipeFBModel
    @ObservedObject private var moderation = ModerationStore.shared

    // Moderation UI state (App Store Guideline 1.2: users must be able to
    // flag content and block abusive authors; deleting own content is recommended).
    @State private var showReportDialog = false
    @State private var showDeleteConfirm = false
    // Admin moderation: confirm before deleting someone else's public recipe.
    @State private var showAdminDeleteConfirm = false
    // The editor for the author's own recipe, or any public one for an admin.
    @State private var showEditSheet = false
    // Error message shown when a delete fails, so the screen no longer
    // silently dismisses (leaving the recipe in the list) as if it worked.
    @State private var deleteErrorMessage: String?

    // Translation state: switching language re-writes the shared recipeFB, so both tabs update.
    @State private var selectedLanguage = ""
    /// Set once the user picks a language, so the automatic choice stops
    /// interfering with it.
    @State private var hasChosenLanguage = false
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

    /// True when an admin may delete this recipe here: it is public and not the
    /// admin's own (the own one already has "Mein Rezept löschen"). Author-only
    /// recipes are never shared, so they stay out of an admin's reach.
    private var canDeleteAsAdmin: Bool {
        modelFB.isAdmin && !isOwnRecipe && recipeFB.visibility == .everyone
    }

    /// True when this recipe may be changed here: by its author, or by an
    /// admin correcting a public one. The security rules allow the same two
    /// cases, so the entry never offers what the server would refuse.
    private var canEdit: Bool {
        isOwnRecipe || (modelFB.isAdmin && recipeFB.visibility == .everyone)
    }

    var body: some View {
        TabView (selection: $tabSelection) {

            Group {
                if bakingTabOpened {
                    InstructionsFBView(recipeFB: recipeFB, languageCode: selectedLanguage)
                } else {
                    Color.clear
                }
            }
                .tabItem {
                    VStack {
                        Image(systemName: "dial.max.fill")
                        Text("Rezept backen")
                    }
                }
                .tag(Self.bakingTab)

             RecipeFBDetailView(recipeFB: recipeFB)
                .tabItem {
                    VStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Details")
                    }
                }
                .tag(Self.detailsTab)

            // Same place as for a recipe of one's own, so the shopping list is
            // where people look for it.
            NavigationStack {
                ShoppingCartSelectFormView(recipeFB: recipeFB)
            }
                .tabItem {
                    VStack {
                        Image(systemName: "cart")
                        Text("Einkaufsliste")
                    }
                }
                .tag(2)
        }
        // accentText, not accentBottom: the tab bar keeps the system's own
        // background, so the tint has to be light in dark mode, not dark.
        .tint(Theme.accentText)
        .onChange(of: tabSelection) { _, selection in
            if selection == Self.bakingTab { bakingTabOpened = true }
        }
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
                    if canEdit {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Rezept bearbeiten", systemImage: "pencil")
                        }
                    }

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

                    // The same action also sits at the bottom of the Details
                    // tab; here it is reachable from every tab.
                    if canDeleteAsAdmin {
                        Button(role: .destructive) {
                            showAdminDeleteConfirm = true
                        } label: {
                            Label("Rezept löschen (Admin)", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Weitere Aktionen")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditRecipeFBView(recipeFB: recipeFB) {
                recipeWasEdited()
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
        .confirmationDialog("Öffentliches Rezept löschen?", isPresented: $showAdminDeleteConfirm, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                modelFB.deleteRecipeAsAdmin(recipeFB) { result in
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
            Text("Dieses Rezept wird als Administrator endgültig aus der öffentlichen Datenbank entfernt.")
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
            applyInitialLanguage()
        }
        // The recipe's language is read off its steps, which arrive a moment
        // after the screen does. Without this the menu would keep the mark it
        // guessed from the name alone.
        .onChange(of: recipeFB.instructions.count) { _, _ in
            guard !hasChosenLanguage else { return }
            selectedLanguage = ""
            applyInitialLanguage()
        }
    }

    /// Marks the language the recipe is shown in when the screen opens: the
    /// user's own if a translation for it exists, otherwise the original.
    private func applyInitialLanguage() {
        guard selectedLanguage.isEmpty else { return }

        selectedLanguage = RecipeTranslator.showCachedIfAvailable(recipeFB, languageCode: RecipeFB.preferredLanguageCode)
            ? RecipeFB.preferredLanguageCode
            : RecipeTranslator.sourceLanguageCode(for: recipeFB)
    }

    /// After a save the recipe shows its original text and its other
    /// translations are gone, so the language mark has to follow; the
    /// automatic choice may take over again as well.
    private func recipeWasEdited() {
        hasChosenLanguage = false
        selectedLanguage = RecipeTranslator.sourceLanguageCode(for: recipeFB)
    }

    /// Switches the displayed language for the shared recipe, translating on-device when needed.
    private func select(_ code: String) {
        guard code != selectedLanguage, !isTranslating else { return }
        hasChosenLanguage = true

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
