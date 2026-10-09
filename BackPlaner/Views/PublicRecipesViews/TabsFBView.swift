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

    // Settings → Übersetzung: whether a recipe is translated into the app's
    // language automatically, and whether the globe menu offers a language
    // choice at all. Off, the recipe always stays in its original language.
    @AppStorage(AppSettingsKeys.automaticTranslation) private var automaticTranslation = AppSettings.defaultAutomaticTranslation

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
    /// True while the recipe is translated into the app's language without
    /// the user having asked; a failure then stays in the log instead of
    /// greeting them with an alert.
    @State private var isAutomaticTranslation = false

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
            // finished yet. The language is settled only once everything is
            // here: a translation started earlier would miss the ingredients
            // still on their way.
            modelFB.loadDetails(of: recipeFB) {
                applyInitialLanguage()
            }
            // Re-evaluate admin status here too, in case the anonymous sign-in or
            // the admins document became available after launch.
            modelFB.checkAdminStatus()
        }
        .toolbar {
            // The globe only has to appear when nothing already settled the
            // language automatically: with automatic translation on, picking
            // one by hand would just redo what already happened.
            if !automaticTranslation {
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
                if isAutomaticTranslation {
                    // Nobody asked for it, so nobody is told; the original
                    // stays on screen and the globe menu still works.
                    AppLog.firebase.error("Automatic translation into \(target) failed: \(error.localizedDescription)")
                } else {
                    translationError = error.localizedDescription
                }
            }
            isTranslating = false
            isAutomaticTranslation = false
            pendingLanguage = nil
        }
        .alert("Übersetzung fehlgeschlagen",
               isPresented: Binding(get: { translationError != nil },
                                    set: { if !$0 { translationError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(translationError ?? "")
        }
    }

    /// Shows the recipe in the app's language once all of its parts have
    /// loaded: from the cache when a complete translation exists, otherwise
    /// by translating it now. A French or English user should not have to
    /// find the globe menu to read a German recipe — and the other way
    /// round. The original stays if the language is one the app does not
    /// translate into, or if automatic translation is off in the settings.
    private func applyInitialLanguage() {
        guard selectedLanguage.isEmpty else { return }

        guard automaticTranslation else {
            selectedLanguage = RecipeTranslator.sourceLanguageCode(for: recipeFB)
            return
        }

        let preferred = RecipeFB.preferredLanguageCode
        let source = RecipeTranslator.sourceLanguageCode(for: recipeFB)

        if RecipeTranslator.showCompleteIfAvailable(recipeFB, languageCode: preferred) {
            selectedLanguage = preferred
            return
        }

        selectedLanguage = source
        guard RecipeTranslator.supportedLanguages.contains(where: { $0.code == preferred }) else { return }

        isAutomaticTranslation = true
        startTranslation(into: preferred)
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

        if RecipeTranslator.showCompleteIfAvailable(recipeFB, languageCode: code) {
            selectedLanguage = code
            return
        }

        isAutomaticTranslation = false
        startTranslation(into: code)
    }

    /// Hands the recipe to the translation task above. The original goes back
    /// on screen first: the recipe list may have translated the name and
    /// summary ahead of time, and the task snapshots the source text from
    /// what it finds on screen.
    private func startTranslation(into code: String) {
        let source = RecipeTranslator.sourceLanguageCode(for: recipeFB)
        if recipeFB.hasCachedTranslation(languageCode: source) {
            recipeFB.showLocalization(languageCode: source)
        }
        selectedLanguage = source
        pendingLanguage = code

        let configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: source),
            target: Locale.Language(identifier: code)
        )
        // The task only runs again when its configuration changes; the same
        // pair a second time (an automatic attempt failed, now the user asks)
        // has to be invalidated instead.
        if translationConfig == configuration {
            translationConfig?.invalidate()
        } else {
            translationConfig = configuration
        }
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
