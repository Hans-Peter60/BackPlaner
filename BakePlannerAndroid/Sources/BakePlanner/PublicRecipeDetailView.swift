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
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let content {
                page(of: content)
            } else if let loadError {
                VStack(spacing: 12) {
                    Text("Das Rezept konnte nicht geladen werden.")
                    Text(verbatim: loadError)
                        .font(.caption)
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
                    Button("Rezept melden", role: .destructive) {
                        choosesReportReason = true
                    }
                    Button("Autor blockieren", role: .destructive) {
                        model.blockAuthor(of: recipe)
                        dismiss()
                    }
                } label: {
                    Label("Weitere Aktionen", systemImage: "ellipsis")
                }
            }
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

    private func page(of content: RecipeExportData) -> some View {
        let page = RecipePrintData(data: content, scale: scale, bakersPercentages: model.showsBakersPercentages)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecipePicture(data: content.image)

                // Skip has no globe symbol; the word says it.
                Text("Öffentlich")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !page.summary.isEmpty {
                    Text(verbatim: page.summary)
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
                .font(.subheadline)

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

                RecipeLineSections(page: page)
            }
            .padding()
        }
    }
}
