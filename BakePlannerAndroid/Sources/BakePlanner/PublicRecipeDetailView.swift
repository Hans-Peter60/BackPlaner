import BakePlannerCore
import SwiftUI

/// A public recipe: its picture, summary, amount, dough yield, components,
/// total ingredients and steps, as the own recipes show them. Components,
/// steps and picture are read when the recipe is first opened. It can be
/// planned (which keeps an own copy, as on the iPhone), put on a shopping
/// list, and saved as an own recipe; reported, or its author blocked, which
/// takes it out of the list (as the iPhone does, and Google Play asks for).
struct PublicRecipeDetailView: View {
    let model: AppModel
    let recipe: RecipeFB
    @State var content: RecipeExportData?
    @State var loadError: String?
    /// The factor on the recipe as published: 1 is the recipe, 2 twice as much.
    @State var scale = 1.0
    /// The own copy as the plan works from it (PublicRecipeCopy); its key is
    /// empty, the copy is kept only when the plan is saved.
    @State var planRecipe: StoredRecipe?
    @State var plans = false
    @State var addsToShoppingList = false
    /// Whether saving as an own recipe worked. Kept apart from the alert's
    /// visibility: Android closes the alert before it runs its button.
    @State var savedCopy = false
    @State var showsSaveOutcome = false
    @State var choosesReportReason = false
    /// The tapped flour or starter line, on the own copy the adjustment
    /// would be written into. Kept apart from the sheets' visibility.
    @State var lineRequest: IngredientLineRequest?
    @State var substitutesFlour = false
    @State var adjustsStarter = false
    /// The adjusted copy to open once its sheet has gone.
    @State var keptRecipeID: String?
    @State var opensKeptRecipe = false
    /// Editing and removing, for the author and for admins. Kept apart
    /// from the dialogs' visibility, as the dialogs' data is.
    @State var edits = false
    @State var confirmsOwnDeletion = false
    @State var confirmsAdminDeletion = false
    @State var isWorking = false
    @State var actionFailure: String?
    @State var showsActionFailure = false
    @State var sharingFailed = false
    @Environment(\.colorScheme) var colorScheme

    private var isOwn: Bool { model.isOwn(recipe) }
    /// An admin may change any recipe, as the rules allow; the author his own.
    private var canEdit: Bool { isOwn || model.account.isAdmin }
    private var canDeleteAsAdmin: Bool { model.account.isAdmin && !isOwn }
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            WarmBackdrop()
                .ignoresSafeArea()

            if let content {
                page(of: content)
            } else if let loadError {
                VStack(spacing: 12) {
                    Text("Das Rezept konnte nicht geladen werden.")
                    Text(verbatim: loadError)
                        .font(AppFont.caption)
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(recipe.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let content {
                        Button("Rezept teilen") {
                            sharingFailed = !RecipePDFSharing.share(
                                RecipePrintData(data: content, scale: scale, bakersPercentages: model.showsBakersPercentages))
                        }
                    }
                    if canEdit, content != nil {
                        Button("Rezept bearbeiten") {
                            edits = true
                        }
                    }
                    Button("Rezept melden", role: .destructive) {
                        choosesReportReason = true
                    }
                    Button("Autor blockieren", role: .destructive) {
                        model.blockAuthor(of: recipe)
                        dismiss()
                    }
                    if isOwn {
                        Button("Mein Rezept löschen", role: .destructive) {
                            confirmsOwnDeletion = true
                        }
                    }
                    if canDeleteAsAdmin {
                        Button("Rezept löschen (Admin)", role: .destructive) {
                            confirmsAdminDeletion = true
                        }
                    }
                } label: {
                    Label("Weitere Aktionen", systemImage: "ellipsis")
                }
                .disabled(isWorking)
            }
        }
        .appSheet(isPresented: $edits) {
            if let content {
                NavigationStack {
                    // The same editor as for an own recipe, on the public
                    // recipe's content; saving goes to the database.
                    RecipeEditor(original: nil, template: content, editsPublished: true) { _, edited in
                        Task { await saveEdits(edited) }
                    }
                }
            }
        }
        // Not the iPhone's "Mein Rezept löschen?": Xcode would give it the same
        // catalog symbol as the menu entry and refuse the build.
        .confirmationDialog("Mein Rezept endgültig löschen?", isPresented: $confirmsOwnDeletion, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task { await deleteRecipe() }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Das Rezept wird endgültig aus der öffentlichen Datenbank entfernt.")
        }
        .confirmationDialog("Öffentliches Rezept löschen?", isPresented: $confirmsAdminDeletion, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                Task { await deleteRecipe() }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Das Rezept wird endgültig aus der öffentlichen Datenbank entfernt.")
        }
        .alert("Teilen fehlgeschlagen", isPresented: $sharingFailed) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        }
        .alert("Aktion fehlgeschlagen", isPresented: $showsActionFailure) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            Text(verbatim: actionFailure ?? "")
        }
        .confirmationDialog("Rezept melden", isPresented: $choosesReportReason, titleVisibility: .visible) {
            ForEach(RecipeFirestoreMapping.reportReasons, id: \.self) { reason in
                // Shown in the app's language, stored as the German text
                // reviewers read, as the iPhone stores it.
                Button(LocalizedStringKey(reason), role: .destructive) {
                    Task { await model.report(recipe, reason: reason) }
                    dismiss()
                }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Warum meldest Du dieses Rezept? Es wird sofort für alle Nutzer ausgeblendet und anschließend geprüft.")
        }
        .appSheet(isPresented: $plans) {
            if let planRecipe {
                NavigationStack {
                    PlanView(model: model, recipe: planRecipe, scale: scale, takeOver: {
                        await model.takeOver(recipe)
                    })
                }
            }
        }
        .appSheet(isPresented: $addsToShoppingList) {
            if let content {
                NavigationStack {
                    AddToShoppingListView(model: model, source: .shared(content), scale: scale)
                }
            }
        }
        .appSheet(isPresented: $substitutesFlour) {
            if let lineRequest {
                NavigationStack {
                    FlourSubstitutionSheet(model: model, request: lineRequest, onKept: showKept)
                }
            }
        }
        .appSheet(isPresented: $adjustsStarter) {
            if let lineRequest {
                NavigationStack {
                    StarterYieldSheet(model: model, request: lineRequest, onKept: showKept)
                }
            }
        }
        // The adjusted own copy opens as the next page, as on the iPhone.
        .navigationDestination(isPresented: $opensKeptRecipe) {
            RecipeDetailView(model: model, recipeID: keptRecipeID ?? "")
        }
        .alert(savedCopy ? LocalizedStringKey("Rezept wurde gespeichert") : LocalizedStringKey("Speichern fehlgeschlagen"),
               isPresented: $showsSaveOutcome) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            if savedCopy {
                Text("Das Rezept steht jetzt bei Deinen Rezepten auf diesem Gerät. Dort kannst Du es bearbeiten, ohne das öffentliche Rezept zu verändern.")
            }
        }
        .task {
            do {
                content = try await model.publicRecipeContent(recipe)
            } catch {
                logger.error("could not read public recipe \(recipe.id ?? ""): \(error)")
                loadError = error.localizedDescription
            }
        }
    }

    /// Writes the edit to the database and shows the recipe as edited.
    private func saveEdits(_ edited: RecipeExportData) async {
        isWorking = true
        defer { isWorking = false }
        if let failure = await model.saveEdits(of: recipe, content: edited) {
            actionFailure = failure
            showsActionFailure = true
            return
        }
        content = RecipeExportData(recipeFB: recipe, imageData: model.publicRecipeImages[recipe.id ?? ""])
    }

    private func deleteRecipe() async {
        isWorking = true
        defer { isWorking = false }
        if let failure = await model.deletePublic(recipe) {
            actionFailure = failure
            showsActionFailure = true
            return
        }
        dismiss()
    }

    private func release() async {
        isWorking = true
        defer { isWorking = false }
        if let failure = await model.release(recipe) {
            actionFailure = failure
            showsActionFailure = true
        }
    }

    private func page(of content: RecipeExportData) -> some View {
        let page = RecipePrintData(data: content, scale: scale, bakersPercentages: model.showsBakersPercentages)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecipePicture(data: content.image)

                // Skip has no globe symbol; the word says it.
                Text(isOwn ? LocalizedStringKey("Von mir veröffentlicht") : LocalizedStringKey("Öffentlich"))
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)

                if isWorking {
                    ProgressView()
                }

                // An admin reviews a reported recipe here and can release it.
                if model.account.isAdmin, recipe.hidden {
                    Text("Dieses Rezept wurde gemeldet und ist für alle anderen Nutzer ausgeblendet.")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.red)
                    Button("Rezept wieder freigeben") {
                        Task { await release() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }

                // Description, amount and the facts on one card, as the
                // iPhone's Details tab has them.
                VStack(alignment: .leading, spacing: 10) {
                    if !page.summary.isEmpty {
                        Text(verbatim: page.summary)
                            .font(AppFont.body)
                    }
                    RecipeLinkRow(urlLink: content.urlLink)
                    VStack(alignment: .leading, spacing: 6) {
                        AmountControl(scale: $scale, baseWeight: content.totalWeight)
                        Text("Gesamtgewicht: \(String(page.totalWeight)) g")
                        if !page.prepTime.isEmpty {
                            Text("Bearbeitungsdauer: \(page.prepTime)")
                        }
                        DoughYieldRow(content: content)
                    }
                    .font(AppFont.subheadline)
                }
                .foregroundStyle(Palette.cardTitle(colorScheme))
                .cardStyle()

                // At the amount chosen above, as on the iPhone.
                Button {
                    planRecipe = StoredRecipe(id: "", content: PublicRecipeCopy.content(
                        of: recipe, imageData: model.publicRecipeImages[recipe.id ?? ""]))
                    plans = true
                } label: {
                    Label("Planen", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
                .tint(Palette.accent(colorScheme))

                Button {
                    addsToShoppingList = true
                } label: {
                    Label("Rezept zur Einkaufsliste hinzufügen", systemImage: "cart")
                }
                .buttonStyle(.bordered)
                .tint(Palette.accent(colorScheme))

                Button {
                    Task {
                        savedCopy = await model.takeOver(recipe) != nil
                        showsSaveOutcome = true
                    }
                } label: {
                    Label("Als eigenes Rezept speichern", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .tint(Palette.accent(colorScheme))

                // Flour and starter lines are tappable as on an own recipe;
                // the adjustment is written into a new own copy, built as
                // "Als eigenes Rezept speichern" would build it.
                RecipeLineSections(page: page, content: content, onFlourTap: { component, ingredient in
                    lineRequest = IngredientLineRequest(recipe: copyToAdjust(), componentIndex: component,
                                                        ingredientIndex: ingredient, scale: scale)
                    substitutesFlour = true
                }, onStarterTap: { component, ingredient in
                    lineRequest = IngredientLineRequest(recipe: copyToAdjust(), componentIndex: component,
                                                        ingredientIndex: ingredient, scale: scale)
                    adjustsStarter = true
                })
            }
            .padding()
        }
    }

    /// The own copy an adjustment starts from: not stored yet (empty key,
    /// no adjustment date), so the sheet offers "Kopie anlegen".
    private func copyToAdjust() -> StoredRecipe {
        StoredRecipe(id: "", content: PublicRecipeCopy.content(of: recipe, imageData: model.publicRecipeImages[recipe.id ?? ""]))
    }

    private func showKept(_ kept: StoredRecipe) {
        keptRecipeID = kept.id
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            opensKeptRecipe = true
        }
    }
}
