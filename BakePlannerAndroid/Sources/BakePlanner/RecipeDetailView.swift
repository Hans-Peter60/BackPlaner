import BakePlannerCore
import SkipKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One recipe: its picture, the dough yield, the components with their
/// ingredients, the total ingredients and the steps — at the amount chosen
/// here. The lines come from RecipePrintData, the same preparation the iOS
/// app prints from, so units and fractions read alike on both platforms.
struct RecipeDetailView: View {
    let model: AppModel
    let recipeID: String
    @State var recipe: StoredRecipe?
    /// The factor on the recipe as stored: 1 is the recipe, 2 twice as much.
    @State var scale = 1.0
    @State var isEditing = false
    @State var picksImage = false
    @State var takesPhoto = false
    @State var recipeToExport: [String]?
    @State var pickedImageURL: URL?
    @State var pickedImageName: String?
    @State var pickedImageType: String?
    @State var addsToShoppingList = false
    @State var plans = false
    /// The tapped flour or starter line. Kept apart from the sheets'
    /// visibility, as the dialogs' data is.
    @State var lineRequest: IngredientLineRequest?
    @State var substitutesFlour = false
    @State var adjustsStarter = false
    /// The adjusted copy to open once its sheet has gone.
    @State var keptRecipeID: String?
    @State var opensKeptRecipe = false
    /// Publishing: the terms first (once), then the question, then the
    /// upload; what came of it in an alert. Kept apart from the alerts'
    /// visibility, as the dialogs' data is.
    @State var showsTerms = false
    @State var confirmsPublishing = false
    @State var isPublishing = false
    @State var publishFailure: String?
    @State var showsPublishOutcome = false
    @State var needsSignIn = false
    @State var needsImage = false
    @State var sharingFailed = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.backgroundTop(colorScheme), Palette.backgroundBottom(colorScheme)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if let recipe {
                content(of: recipe)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(recipe?.content.name ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Bearbeiten") {
                    isEditing = true
                }
                .disabled(recipe == nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        recipeToExport = [recipeID]
                    } label: {
                        Label("Rezept sichern", systemImage: "square.and.arrow.up")
                    }
                    // The page at the amount shown, as the iPhone shares it.
                    if let recipe {
                        Button("Rezept teilen") {
                            sharingFailed = !RecipePDFSharing.share(
                                RecipePrintData(data: recipe.content, scale: scale, bakersPercentages: model.showsBakersPercentages))
                        }
                    }
                    // Publishing wants an account of one's own and a picture;
                    // a recipe that is public already is not offered again.
                    if let recipe, model.canPublish(recipe) {
                        Button("Veröffentlichen") {
                            beginPublishing(recipe)
                        }
                        .disabled(isPublishing)
                    }
                } label: {
                    Label("Weitere Aktionen", systemImage: "ellipsis")
                }
                .disabled(recipe == nil)
            }
        }
        .appSheet(isPresented: $showsTerms) {
            NavigationStack {
                TermsView {
                    model.hasAcceptedTerms = true
                    // The question follows once the sheet has gone.
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        confirmsPublishing = true
                    }
                }
            }
        }
        .alert("Rezept veröffentlichen?", isPresented: $confirmsPublishing) {
            Button("Öffentlich speichern") {
                Task { await publish() }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Das Rezept wird für alle Nutzer sichtbar. Als Autor kannst Du es später in der Rezept-Datenbank bearbeiten oder löschen.")
        }
        .alert(publishFailure == nil ? LocalizedStringKey("Rezept wurde gespeichert") : LocalizedStringKey("Upload fehlgeschlagen"),
               isPresented: $showsPublishOutcome) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            if let publishFailure {
                Text(verbatim: publishFailure)
            } else {
                Text("Das Rezept ist jetzt für alle Nutzer in der Rezept-Datenbank sichtbar.")
            }
        }
        .alert("Anmeldung nötig", isPresented: $needsSignIn) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            Text("Zum Veröffentlichen melde Dich in den Einstellungen unter „Konto“ mit Apple an. So gehört das Rezept Dir auf allen Geräten.")
        }
        .alert("Teilen fehlgeschlagen", isPresented: $sharingFailed) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        }
        .alert("Bild erforderlich", isPresented: $needsImage) {
            Button {
            } label: {
                Text(verbatim: "OK")
            }
        } message: {
            Text("Das Rezept kann nicht gespeichert werden. Bitte füge zuerst ein Rezeptbild hinzu.")
        }
        .recipeFileExporter(model: model, recipeIDs: $recipeToExport, fileName: recipe?.content.name ?? "Rezept",
                            includesBakeHistory: false)
        .appSheet(isPresented: $isEditing) {
            if let recipe {
                NavigationStack {
                    RecipeEditor(original: recipe) { _, content in
                        var edited = recipe
                        edited.content = content
                        // `update` leaves the picture alone; a changed one
                        // goes through setImage.
                        if model.save(edited) {
                            if content.image != recipe.content.image {
                                model.setImage(content.image, forRecipe: recipeID)
                            }
                            self.recipe = model.recipe(id: recipeID)
                        }
                    }
                }
            }
        }
        .appSheet(isPresented: $plans) {
            if let recipe {
                NavigationStack {
                    PlanView(model: model, recipe: recipe, scale: scale)
                }
            }
        }
        .appSheet(isPresented: $addsToShoppingList) {
            NavigationStack {
                AddToShoppingListView(model: model, source: .own(recipeID), scale: scale)
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
        // The new copy opens as the next page, as on the iPhone.
        .navigationDestination(isPresented: $opensKeptRecipe) {
            RecipeDetailView(model: model, recipeID: keptRecipeID ?? recipeID)
        }
        .withDocumentPicker(isPresented: $picksImage,
                            allowedContentTypes: [.image],
                            selectedDocumentURL: $pickedImageURL,
                            selectedFilename: $pickedImageName,
                            selectedFileMimeType: $pickedImageType)
        .onChange(of: pickedImageURL) { _, url in
            guard let url else { return }
            pickedImageURL = nil
            // A file that is no picture leaves the recipe's picture as it is.
            guard let data = Self.pictureData(at: url) else { return }
            changeImage(to: data)
        }
        .cameraPicker(isPresented: $takesPhoto) { data in
            changeImage(to: data)
        }
        .task {
            recipe = model.recipe(id: recipeID)
        }
    }

    /// After a flour or starter adjustment: a changed copy on screen is
    /// reloaded, a new copy opened once the sheet has gone.
    private func showKept(_ kept: StoredRecipe) {
        if kept.id == recipeID {
            recipe = model.recipe(id: recipeID)
            return
        }
        keptRecipeID = kept.id
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            opensKeptRecipe = true
        }
    }

    private func content(of recipe: StoredRecipe) -> some View {
        let page = RecipePrintData(data: recipe.content, scale: scale, bakersPercentages: model.showsBakersPercentages)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RecipePicture(data: recipe.content.image)

                if isPublishing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Rezept wird hochgeladen …")
                    }
                    .font(AppFont.subheadline)
                } else if !model.canPublish(recipe) {
                    // Public already: the word stands where the public
                    // recipe's view says "Öffentlich".
                    Text("Veröffentlicht")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    Button(recipe.content.image == nil ? LocalizedStringKey("Bild hinzufügen") : LocalizedStringKey("Bild ändern")) {
                        picksImage = true
                    }
                    Button("Kamera") {
                        takesPhoto = true
                    }
                    if recipe.content.image != nil {
                        Button("Bild entfernen", role: .destructive) {
                            changeImage(to: nil)
                        }
                    }
                }
                .font(AppFont.subheadline)

                // Description, amount and the facts on one card, as the
                // iPhone's Details tab has them.
                VStack(alignment: .leading, spacing: 10) {
                    if !page.summary.isEmpty {
                        Text(verbatim: page.summary)
                            .font(AppFont.body)
                    }
                    RecipeLinkRow(urlLink: recipe.content.urlLink)
                    VStack(alignment: .leading, spacing: 6) {
                        AmountControl(scale: $scale, baseWeight: recipe.content.totalWeight)
                        Text("Gesamtgewicht: \(String(page.totalWeight)) g")
                        if !page.prepTime.isEmpty {
                            Text("Bearbeitungsdauer: \(page.prepTime)")
                        }
                        DoughYieldRow(content: recipe.content)
                        if recipe.content.recurrenceIntervalDays > 0 {
                            Self.nextRhythmText(date: model.nextRhythmStart(of: recipe),
                                                isStarter: StarterRecipe.isStarterFeeding(recipe.content))
                                .foregroundStyle(Palette.accentText(colorScheme))
                        }
                    }
                    .font(AppFont.subheadline)
                }
                .foregroundStyle(Palette.cardTitle(colorScheme))
                .cardStyle()

                // At the amount chosen above, as on the iPhone.
                Button {
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

                RecipeLineSections(page: page, content: recipe.content, onFlourTap: { component, ingredient in
                    lineRequest = IngredientLineRequest(recipe: recipe, componentIndex: component,
                                                        ingredientIndex: ingredient, scale: scale)
                    substitutesFlour = true
                }, onStarterTap: { component, ingredient in
                    lineRequest = IngredientLineRequest(recipe: recipe, componentIndex: component,
                                                        ingredientIndex: ingredient, scale: scale)
                    adjustsStarter = true
                })

                // A starter is fed, not baked: it keeps a feeding diary and
                // no bake history; every other recipe the other way round.
                if StarterRecipe.isStarterFeeding(recipe.content) {
                    StarterFeedingSection(model: model, recipeID: recipeID,
                                          ratio: StarterFeedingRatio.ratio(for: recipe.content))
                } else {
                    RecipeBakeHistorySection(model: model, recipeID: recipeID)
                }
            }
            .padding()
        }
    }

    /// Publishing starts with its conditions — signed in, a picture — then
    /// the terms once, then the question.
    private func beginPublishing(_ recipe: StoredRecipe) {
        guard model.account.isSignedInWithApple else {
            needsSignIn = true
            return
        }
        guard recipe.content.image != nil else {
            needsImage = true
            return
        }
        if model.hasAcceptedTerms {
            confirmsPublishing = true
        } else {
            showsTerms = true
        }
    }

    private func publish() async {
        isPublishing = true
        publishFailure = await model.publish(recipeID: recipeID)
        isPublishing = false
        recipe = model.recipe(id: recipeID)
        showsPublishOutcome = true
    }

    private func changeImage(to data: Data?) {
        if model.setImage(data, forRecipe: recipeID) {
            recipe = model.recipe(id: recipeID)
        }
    }

    /// The picked picture as JPEG, the way the iOS app keeps pictures; nil
    /// when the file is no picture.
    static func pictureData(at url: URL) -> Data? {
        #if !os(Android)
        // On iOS the picked file is only readable while its access lasts;
        // on Android the picker hands over a copy in the app's cache.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #endif
        guard let data = try? Data(contentsOf: url) else { return nil }
        // JPEG, and no larger than looks sharp on screen (PhotoShrinker).
        return PhotoShrinker.pickedPhoto(data)
    }

    /// "Nächste Fütterung: Mi., 4.11. 08:00", as on the iPhone; before the
    /// first bake or feeding, when that will be.
    static func nextRhythmText(date: Date?, isStarter: Bool) -> Text {
        switch (isStarter, date) {
        case (true, let date?):
            return Text("Nächste Fütterung: \(PlanText.day(date)) \(PlanText.time(date))")
        case (true, nil):
            return Text("Nächste Fütterung: nach der ersten Fütterung")
        case (false, let date?):
            return Text("Nächster Backtermin: \(PlanText.day(date)) \(PlanText.time(date))")
        case (false, nil):
            return Text("Nächster Backtermin: nach dem ersten Backen")
        }
    }

    /// "1", "1,5" in the device's language.
    static func factorText(_ scale: Double) -> String {
        scale.formatted(.number.precision(.fractionLength(0...1)))
    }
}
