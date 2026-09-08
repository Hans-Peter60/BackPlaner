//
//  EditRecipeView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 01.01.22.
//

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
    @State private var componentName   = ""
    @State private var componentNumber = 0
    @State private var tags            = [String]()
    
    @State private var showingAlert = false
    @State private var showingSheet = false
    @State private var activatePublicSaveButton = true
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

    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .trailing)]
    private let instructionGridLayout = [GridItem(.fixed(40), alignment: .leading), GridItem(.flexible(minimum: 100), alignment: .leading), GridItem(.fixed(60), alignment: .trailing), GridItem(.fixed(44), alignment: .trailing)]

    private var canSave: Bool {
        !recipeFB.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Speichern")
                        .font(Theme.brandFont(16))
                        .foregroundColor(Theme.title)

                    HStack(spacing: 12) {
                        IconActionButton(systemImage: "lock", style: .primary, accessibilityLabel: "Privat speichern", title: "Privat speichern", controlSize: .regular) {
                            savePrivateRecipe()
                        }
                        .disabled(!canSave || isUploading)

                        IconActionButton(systemImage: "tray.and.arrow.up", style: .primary, accessibilityLabel: "Öffentlich speichern", title: "Öffentlich speichern", controlSize: .regular) {
                            showPublicSaveWarning = true
                        }
                        .disabled(!activatePublicSaveButton || !canSave || isUploading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                
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
                    HStack {
                        TextField(".", value: $componentNumber, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 40)
                        TextField("...", text: $componentName)
                            .textFieldStyle(.roundedBorder)
                        
                        IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Komponente hinzufügen", controlSize: .regular) {
                            // Make sure that the fields are populated
                            let cleanedName = componentName.trimmingCharacters(in: .whitespacesAndNewlines)

                            // Check that all the fields are filled in
                            if cleanedName == "" { return }

                            // Create an ComponentFB object and set its properties

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
                    }
                        
                    if recipeId != nil {
                        EditComponentDataView(recipeId: recipeId!)
                    }
              
                    Divider()
                    
                    // MARK: Instructions
                    Text("Verarbeitungsschritte")
                        .font(Theme.brandFont(16))
                        .foregroundColor(Theme.title)
                        .padding(.bottom, 3)
                    
                    LazyVGrid(columns: instructionGridLayout, spacing: 6) {
                        Text("Schritt").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                        Text(" ").bold()
                        
                        TextField("", value: $step, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("...", text: $instruction)
                            .textFieldStyle(.roundedBorder)
                        TextField("", value: $duration, formatter: GlobalVariables.formatter)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        
                        IconActionButton(systemImage: "plus", style: .primary, accessibilityLabel: "Schritt hinzufügen", controlSize: .regular) {
                            // Make sure that the fields are populated
                            let cleanedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)

                            // Check that all the fields are filled in
                            if cleanedInstruction == "" { return }

                            // Create an Instruction object and set its properties

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
                    }
                    
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

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                IconActionButton(systemImage: "tray.and.arrow.up", style: .primary, accessibilityLabel: "Öffentlich speichern", title: "Öffentlich", controlSize: .regular) {
                    showPublicSaveWarning = true
                }
                .disabled(!activatePublicSaveButton || !canSave || isUploading)

                IconActionButton(systemImage: "lock", style: .primary, accessibilityLabel: "Privat speichern", title: "Privat", controlSize: .regular) {
                    savePrivateRecipe()
                }
                .disabled(!canSave || isUploading)
            }
        }
        .alert("Rezept wurde gespeichert", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        }
        .sheet(isPresented: $showEULA) {
            EULAView {
                savePublicRecipe()
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
        .alert("Öffentliches Rezept kann nicht geändert werden", isPresented: $showPublicSaveWarning) {
            Button("Abbrechen", role: .cancel) { }
            Button("Öffentlich speichern") {
                continuePublicSaveAfterWarning()
            }
        } message: {
            Text("Ein öffentliches Rezept kann nach dem Speichern nicht mehr geändert werden.")
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
            recipeFB.prepTime        = recipe.prepTime
            recipeFB.bakeHistoryFlag = recipe.bakeHistoryFlag
            recipeFB.tags            = recipe.tags
            recipeImage              = UIImage(data: recipe.image) ?? UIImage()
            
            if let firestoreId = recipe.firestoreId, !firestoreId.isEmpty {
                activatePublicSaveButton = false
                modelFB.publicRecipeExists(id: firestoreId) { result in
                    guard case .success(false) = result else { return }

                    recipe.firestoreId = nil
                    activatePublicSaveButton = true
                    do {
                        try viewContext.save()
                    } catch {
                        AppLog.persistence.error("Could not clear deleted public recipe link: \(error)")
                    }
                }
            } else {
                activatePublicSaveButton = true
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            saveEditableRecipeFields()
        }
        .warmBackground()

    }

    private func recalculateInstructionTimes(for recipe: Recipe) {
        var instructionsFB = recipe.instructionsArray.map { instruction in
            let instructionFB = InstructionFB()
            instructionFB.instruction = instruction.instruction
            instructionFB.step        = instruction.step
            instructionFB.startTime   = instruction.startTime
            instructionFB.duration    = instruction.duration
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
            savePublicRecipe()
        }
    }

    // MARK: Save public recipe
    private func savePublicRecipe() {
        guard
            let objectId = recipeId,
            let recipe = model.fetchRecipe(for: objectId, context: viewContext)
        else {
            return
        }

        autosaveTask?.cancel()
        saveEditableRecipeFields(includeImage: true, recalculateWeight: true)

        let publicRecipe = recipeFB(from: recipe)
        let publicImage = recipeImage ?? UIImage(data: recipe.image) ?? UIImage()

        isUploading = true
        modelFB.uploadRecipeToFirestore(r: publicRecipe, i: publicImage) { result in
            isUploading = false
            switch result {
            case .success:
                recipe.firestoreId = publicRecipe.id
                activatePublicSaveButton = false
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
            return instructionFB
        }

        publicRecipe.capturePreferredLocalization()
        return publicRecipe
    }
}
