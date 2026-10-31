//
//  EditRecipeView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 01.01.22.
//

import BakePlannerCore
import SwiftUI
import CoreData
import Combine
import os

struct EditRecipeView: View {
    @Environment(\.managedObjectContext) var viewContext
    
    var recipeId: NSManagedObjectID?
    
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel

    @State private var recipeFB = RecipeFB()
    
    // Recipe Image
    @State private var recipeImage: UIImage?
    @State private var rating          = 0
    /// 0 disables the recurrence; a personal scheduling preference, so it
    /// lives on `recipe` directly rather than in `recipeFB` — it has no
    /// business syncing to the public, shareable copy of this recipe.
    @State private var recurrenceIntervalDays = 0
    /// The finish the rhythm is measured from — the last bake, or for a
    /// starter its last feeding — for the next date under the stepper.
    @State private var rhythmFinish: Date?
    @State private var componentName   = ""
    @State private var componentNumber = 0
    @State private var tags            = [String]()

    /// Purely visual placeholders. Passing a `String` instead of a
    /// `LocalizedStringKey` keeps them out of the String Catalog.
    private let numberPlaceholder = "."
    private let namePlaceholder   = "..."

    @State private var showingAlert = false
    @State private var showingSheet = false
    /// False once this recipe has a copy in the recipe database. A published
    /// recipe is edited there, so it may only be uploaded once.
    @State private var activateCloudSaveButtons = true
    @State private var showEULA = false
    @State private var showPublicSaveWarning = false
    @State private var isUploading = false
    @State private var uploadErrorMessage: String?
    @State private var showMissingImageAlert = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var selectedComponentId:   NSManagedObjectID?
    @State private var selectedIngredientId:  NSManagedObjectID?
    @State private var selectedInstructionId: NSManagedObjectID?
    @State private var instruction  = ""
    @State private var step         = 0.0
    @State private var duration     = 0

    var gridItemLayout = [GridItem(scaledColumnSize(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(scaledColumnSize(100), alignment: .trailing)]
    private let instructionGridLayout = [GridItem(scaledColumnSize(40), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(scaledColumnSize(60), alignment: .trailing), GridItem(scaledColumnSize(44), alignment: .trailing)]

    private var canSave: Bool {
        !recipeFB.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // The two entry rows are their own views: inline in `body` the whole
    // screen became too much for the type checker in one go.

    /// Number and name of a new component, with the button that adds it.
    private var componentEntryRow: some View {
        HStack {
            NumberField(numberPlaceholder, value: $componentNumber)
                .textFieldStyle(.roundedBorder)
                .frame(width: 40)
                .accessibilityLabel("Nummer")
            TextField(namePlaceholder, text: $componentName)
                .textFieldStyle(.roundedBorder)
                // The placeholders are example values, not names.
                .accessibilityLabel("Komponente")

            IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Komponente hinzufügen", controlSize: .regular) {
                addComponent()
            }
        }
    }

    private func addComponent() {
        // Make sure that the fields are populated
        let cleanedName = componentName.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check that all the fields are filled in
        if cleanedName == "" { return }

        guard
            let objectId = recipeId,
            let recipeCD = model.fetchRecipe(for: objectId, context: viewContext)
        else {
            return
        }

        let c      = Component(context: viewContext)
        c.id       = UUID()
        c.name     = cleanedName
        if componentNumber == 0 {
            c.number = recipeCD.components.count
        }
        else {
            c.number = componentNumber
        }

        recipeCD.addToComponents(c)

        componentName = ""
    }

    /// Step, text and duration of a new instruction, with the button that adds it.
    private var instructionEntryGrid: some View {
        LazyVGrid(columns: instructionGridLayout, spacing: 6) {
            Text("Schritt").bold()
            Text("Beschreibung").bold()
            Text("Dauer").bold()
            Text(verbatim: " ").bold()

            NumberField("", value: $step)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Schritt")
            TextField(namePlaceholder, text: $instruction)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Beschreibung")
            DurationField(minutes: $duration)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Dauer")

            IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Schritt hinzufügen", controlSize: .regular) {
                addInstruction()
            }
        }
        .scrollsSidewaysAtLargeText()
    }

    private func addInstruction() {
        // Make sure that the fields are populated
        let cleanedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check that all the fields are filled in
        if cleanedInstruction == "" { return }

        guard
            let objectId = recipeId,
            let recipeCD = model.fetchRecipe(for: objectId, context: viewContext)
        else {
            return
        }

        let i         = Instruction(context: viewContext)
        i.id          = UUID()
        i.instruction = cleanedInstruction
        i.step        = step
        i.duration    = duration

        recipeCD.addToInstructions(i)
        // "nach 30 und 60 Minuten dehnen und falten" becomes one step per
        // fold, as it does on import.
        TimedFoldExpansion.expand(in: recipeCD, context: viewContext)
        recalculateInstructionTimes(for: recipeCD)
        try? viewContext.save()

        if Double(Int(step)) == step {
            step += 1
        } else {
            step += 0.1
        }
        instruction = ""
        duration    = 0
    }

    private var hasRecipeImage: Bool {
        guard let recipeImage else { return false }
        return recipeImage.size.width > 0 && recipeImage.size.height > 0
    }

    // Image Picker
    @State private var isShowingImagePicker = false
    @State private var selectedImageSource  = UIImagePickerController.SourceType.photoLibrary
    @State private var placeHolderImage     = Image(systemName: "photo")

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    // MARK: Recipe Image
                    VStack(spacing: 6) {
                        Image(uiImage: recipeImage ?? UIImage())
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipped()
                            .cornerRadius(5)
                            .accessibilityLabel("Rezeptbild")

                        IconActionButton(systemImage: "photo.on.rectangle", style: .primary, accessibilityLabel: "Fotomediathek öffnen", title: "Fotomediathek", controlSize: .small) {
                            selectedImageSource  = .photoLibrary
                            isShowingImagePicker = true
                        }
                    }
                    .sheet(isPresented: $isShowingImagePicker, onDismiss: loadImage) {
                        ImagePicker(selectedSource: selectedImageSource, recipeImage: $recipeImage)
                    }

                    Spacer(minLength: 12)

                    // MARK: Rating Stars
                    RatingStarsUpdateView(rating: $rating)
                }

                // The recipe meta data
                AddMetaDataView(name:    $recipeFB.name,
                            summary: $recipeFB.summary,
                            urlLink: $recipeFB.urlLink)
            
                // Tag data
                AddTagsDataView(tags: $recipeFB.tags, title: "Tags", placeholderText: "...")

                // MARK: Recurrence
                // A starter is "refreshed", a bread on a rhythm is "planned";
                // the wording follows what the recipe is.
                let isStarter = StarterRecipe.isStarterFeeding(recipeFB)
                let rhythmTitle: LocalizedStringKey = isStarter ? "Regelmäßig auffrischen" : "Regelmäßig planen"
                VStack(alignment: .leading, spacing: 4) {
                    // A Pro feature: locked, the toggle gives way to a row
                    // that opens the paywall, and the rhythm stays as it is.
                    ProGate(.recurringPlans) {
                        Toggle(rhythmTitle, isOn: Binding(
                            get: { recurrenceIntervalDays > 0 },
                            set: { recurrenceIntervalDays = $0 ? max(recurrenceIntervalDays, 5) : 0 }
                        ))
                        .font(Theme.brandFont(15))
                    } label: {
                        Text(rhythmTitle)
                            .font(Theme.brandFont(15))
                            .foregroundStyle(.primary)
                        Spacer()
                    }

                    if recurrenceIntervalDays > 0, Entitlements.shared.isUnlocked(.recurringPlans) {
                        // The next date follows the stepper live, so the
                        // effect of a changed rhythm shows before saving.
                        Stepper(value: $recurrenceIntervalDays, in: 1...60) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("alle \(recurrenceIntervalDays) Tage")
                                // When the first step is next due: the
                                // feeding of a starter, the first mixing
                                // of a bread.
                                NextFeedingView(date: RecurringBakePlanner.nextStart(
                                    lastFinish: rhythmFinish,
                                    duration: RecurringBakePlanner.planDuration(of: recipeFB),
                                    intervalDays: recurrenceIntervalDays, now: Date()),
                                                isStarter: isStarter)
                            }
                        }
                        .font(Theme.bodyFont(15))
                    }

                    Text("Plant nach dem letzten Backen automatisch den nächsten Termin.")
                        .font(Theme.bodyFont(13))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)

                saveSection
                
                // MARK: Components
                VStack(alignment: .leading) {
                    
                    Text("Komponenten")
                        .font(Theme.brandFont(16))
                        .foregroundColor(Theme.title)
                        .padding(.bottom, 3)
                    
                    HStack {
                        Text("Nr.")
                            .frame(width: 40)
                        Text("Komponente")
                    }
                    componentEntryRow

                    if recipeId != nil {
                        EditComponentDataView(recipeId: recipeId!)
                    }
              
                    Divider()
                    
                    // MARK: Instructions
                    Text("Verarbeitungsschritte")
                        .font(Theme.brandFont(16))
                        .foregroundColor(Theme.title)
                        .padding(.bottom, 3)
                    
                    instructionEntryGrid

                    if recipeId != nil { EditInstructionDataView(recipeId: recipeId!) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(cornerRadius: 8)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .navigationTitle("Rezept bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Rezeptinhalte löschen", title: "Löschen", controlSize: .regular) {
                    clear()
                }
            }

            // A menu instead of one button per target, so the navigation bar
            // keeps a single save symbol.
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        savePrivateRecipe()
                    } label: {
                        Label(RecipeStoragePreference.privateRecipe.title, systemImage: RecipeStoragePreference.privateRecipe.symbolName)
                    }

                    Button {
                        showPublicSaveWarning = true
                    } label: {
                        Label(RecipeStoragePreference.publicRecipe.title, systemImage: RecipeStoragePreference.publicRecipe.symbolName)
                    }
                    .disabled(!activateCloudSaveButtons)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Rezept speichern")
                .disabled(!canSave || isUploading)
            }
        }
        .alert("Rezept wurde gespeichert", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
        .sheet(isPresented: $showEULA) {
            EULAView {
                publishRecipe()
            }
        }
        .alert("Upload fehlgeschlagen", isPresented: Binding(
            get: { uploadErrorMessage != nil },
            set: { if !$0 { uploadErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { uploadErrorMessage = nil }
        } message: {
            Text(uploadErrorMessage ?? "")
        }
        .alert("Bild erforderlich", isPresented: $showMissingImageAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Das Rezept kann nicht gespeichert werden. Bitte füge zuerst ein Rezeptbild hinzu.")
        }
        .alert("Rezept veröffentlichen?", isPresented: $showPublicSaveWarning) {
            Button("Abbrechen", role: .cancel) { }
            Button("Öffentlich speichern") {
                continuePublicSaveAfterWarning()
            }
        } message: {
            Text("Das Rezept wird für alle Nutzer sichtbar. Als Autor kannst Du es später in der Rezept-Datenbank bearbeiten oder löschen.")
        }
        .overlay {
            if isUploading {
                ProgressView("Rezept wird hochgeladen …")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sensoryFeedback(trigger: showingAlert) { _, isShown in
            isShown ? .success : nil
        }
        .onChange(of: rating) { scheduleAutosave() }
        .onChange(of: recurrenceIntervalDays) { scheduleAutosave() }
        .onChange(of: recipeFB.name) { scheduleAutosave() }
        .onChange(of: recipeFB.summary) { scheduleAutosave() }
        .onChange(of: recipeFB.urlLink) { scheduleAutosave() }
        .onChange(of: recipeFB.tags) { scheduleAutosave() }
        .onAppear {
            guard
                let objectId = recipeId,
                let recipe   = model.fetchRecipe(for: objectId, context: viewContext)
            else {
                return
            }
            
            recipeFB.name            = recipe.name
            recipeFB.summary         = recipe.summary
            recipeFB.urlLink         = recipe.urlLink ?? ""
            rating                   = recipe.rating
            recurrenceIntervalDays   = recipe.recurrenceIntervalDays
            // Measured as the recipe view and the automatic planning do: a
            // starter from its last feeding, see `rhythmFinish(of:)`.
            rhythmFinish             = RecurringBakePlanner.rhythmFinish(of: recipe)
            recipeFB.prepTime        = recipe.prepTime
            recipeFB.bakeHistoryFlag = recipe.bakeHistoryFlag
            recipeFB.tags            = recipe.tags
            recipeImage              = UIImage(data: recipe.image) ?? UIImage()
            
            if let firestoreId = recipe.firestoreId, !firestoreId.isEmpty {
                activateCloudSaveButtons = false
                modelFB.cloudRecipeExists(id: firestoreId) { result in
                    guard case .success(false) = result else { return }

                    recipe.firestoreId = nil
                    activateCloudSaveButtons = true
                    do {
                        try viewContext.save()
                    } catch {
                        AppLog.persistence.error("Could not clear deleted cloud recipe link: \(error)")
                    }
                }
            } else {
                activateCloudSaveButtons = true
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            saveEditableRecipeFields()
        }
        .warmBackground()

    }

    /// Where the recipe is saved to. Its own property, so the type checker does
    /// not have to resolve it as part of the (very large) body expression.
    @ViewBuilder
    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speichern")
                .font(Theme.brandFont(16))
                .foregroundColor(Theme.title)

            // The two buttons do not always fit next to each other at larger
            // text sizes, so fall back to stacking them.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { saveButtons }
                VStack(alignment: .leading, spacing: 8) { saveButtons }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    /// Saving on the device, and publishing a copy. The titles stay short so
    /// the row fits; the full meaning is in the accessibility labels.
    @ViewBuilder
    private var saveButtons: some View {
        IconActionButton(systemImage: RecipeStoragePreference.privateRecipe.symbolName,
                         style: .primary,
                         accessibilityLabel: "Nur auf dem Gerät speichern",
                         title: RecipeStoragePreference.privateRecipe.shortTitle,
                         controlSize: .regular) {
            savePrivateRecipe()
        }
        .disabled(!canSave || isUploading)

        IconActionButton(systemImage: RecipeStoragePreference.publicRecipe.symbolName,
                         style: .primary,
                         accessibilityLabel: "Öffentlich speichern",
                         title: RecipeStoragePreference.publicRecipe.shortTitle,
                         controlSize: .regular) {
            showPublicSaveWarning = true
        }
        .disabled(!activateCloudSaveButtons || !canSave || isUploading)
    }

    private func recalculateInstructionTimes(for recipe: Recipe) {
        var instructionsFB = recipe.instructionsArray.map { instruction in
            let instructionFB = InstructionFB()
            instructionFB.instruction = instruction.instruction
            instructionFB.step        = instruction.step
            instructionFB.startTime   = instruction.startTime
            instructionFB.duration    = instruction.duration
            instructionFB.componentName = instruction.componentName
            return instructionFB
        }

        instructionsFB = Rational.calculateStartTimes(
            instructionsFB,
            Date(),
            dependencies: Rational.ComponentDependency.from(recipe.componentsArray)
        )

        for (instruction, instructionFB) in zip(recipe.instructionsArray, instructionsFB) {
            instruction.startTime = instructionFB.startTime ?? 0
            instruction.date      = instructionFB.date
        }

        recipe.prepTime = GlobalVariables.totalDuration
    }

    // MARK: Load image
    func loadImage() {
        guard let recipeImage else { return }

        placeHolderImage = Image(uiImage: recipeImage)
        saveEditableRecipeFields(includeImage: true)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveEditableRecipeFields()
            }
        }
    }

    private func saveEditableRecipeFields(includeImage: Bool = false, recalculateWeight: Bool = false, showConfirmation: Bool = false) {
        guard
            let objectId = recipeId,
            let recipe = model.fetchRecipe(for: objectId, context: viewContext)
        else {
            return
        }

        if includeImage, let recipeImage {
            recipe.image = recipeImage.jpegData(compressionQuality: 1.0) ?? Data()
        }

        recipe.name    = recipeFB.name
        recipe.summary = recipeFB.summary
        recipe.urlLink = recipeFB.urlLink
        recipe.rating  = rating
        recipe.recurrenceIntervalDays = recurrenceIntervalDays
        recipe.tags    = recipeFB.tags

        if recalculateWeight {
            recipe.recalculateTotalWeight()
        }

        do {
            try viewContext.save()
            if showConfirmation {
                showingAlert = true
            }
        } catch {
            AppLog.persistence.error("Couldn't autosave the recipe")
            if showConfirmation {
                showingAlert = false
            }
        }
    }
    
    // MARK: Clear
    func clear() {
        // Clear all the form fields

        autosaveTask?.cancel()
        recipeFB    = RecipeFB()
        recipeImage = UIImage()

        placeHolderImage = Image(systemName: "photo")
        saveEditableRecipeFields(includeImage: true, recalculateWeight: true)
    }

    // MARK: Save private recipe
    func savePrivateRecipe() {
        guard hasRecipeImage else {
            showMissingImageAlert = true
            return
        }

        autosaveTask?.cancel()
        saveEditableRecipeFields(includeImage: true, recalculateWeight: true, showConfirmation: true)
    }

    private func continuePublicSaveAfterWarning() {
        // Publishing to the shared database requires accepting the content agreement first.
        if !ModerationStore.shared.hasAcceptedEULA {
            showEULA = true
        } else {
            publishRecipe()
        }
    }

    // MARK: Publish the recipe
    private func publishRecipe() {
        guard
            let objectId = recipeId,
            let recipe = model.fetchRecipe(for: objectId, context: viewContext)
        else {
            return
        }

        autosaveTask?.cancel()
        saveEditableRecipeFields(includeImage: true, recalculateWeight: true)

        let cloudRecipe = recipeFB(from: recipe)
        let cloudImage = recipeImage ?? UIImage(data: recipe.image) ?? UIImage()

        isUploading = true
        modelFB.uploadRecipeToFirestore(r: cloudRecipe, i: cloudImage) { result in
            isUploading = false
            switch result {
            case .success:
                recipe.firestoreId = cloudRecipe.id
                activateCloudSaveButtons = false
                try? viewContext.save()
                showingAlert = true
            case .failure(let error):
                uploadErrorMessage = error.localizedDescription
            }
        }
    }

    private func recipeFB(from recipe: Recipe) -> RecipeFB {
        let publicRecipe = RecipeFB()
        publicRecipe.name            = recipe.name
        publicRecipe.summary         = recipe.summary
        publicRecipe.urlLink         = recipe.urlLink ?? ""
        publicRecipe.prepTime        = recipe.prepTime
        publicRecipe.totalWeight     = recipe.totalWeight
        publicRecipe.tags            = recipe.tags
        publicRecipe.bakeHistoryFlag = recipe.bakeHistoryFlag
        publicRecipe.rating          = recipe.rating

        publicRecipe.components = recipe.componentsArray.map { component in
            let componentFB = ComponentFB()
            componentFB.name   = component.name
            componentFB.number = component.number
            componentFB.ingredients = component.ingredientsArray.map { ingredient in
                let ingredientFB = IngredientFB()
                ingredientFB.name       = ingredient.name
                ingredientFB.number     = ingredient.number
                ingredientFB.unit       = ingredient.unit ?? ""
                ingredientFB.weight     = ingredient.weight
                ingredientFB.normWeight = ingredient.normWeight
                ingredientFB.num        = ingredient.num
                ingredientFB.denom      = ingredient.denom
                return ingredientFB
            }
            return componentFB
        }

        publicRecipe.instructions = recipe.instructionsArray.map { instruction in
            let instructionFB = InstructionFB()
            instructionFB.instruction = instruction.instruction
            instructionFB.step        = instruction.step
            instructionFB.duration    = instruction.duration
            instructionFB.startTime   = instruction.startTime
            instructionFB.date        = instruction.date
            instructionFB.bakeFlag    = instruction.bakeFlag
            instructionFB.componentName = instruction.componentName
            return instructionFB
        }

        publicRecipe.capturePreferredLocalization()
        return publicRecipe
    }
}
