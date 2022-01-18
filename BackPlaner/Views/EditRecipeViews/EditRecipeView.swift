//
//  EditRecipeView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 01.01.22.
//

import SwiftUI
import CoreData
import Combine

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
    
    @State private var showingSheet = false
    @State private var selectedComponentId:   NSManagedObjectID?
    @State private var selectedIngredientId:  NSManagedObjectID?
    @State private var selectedInstructionId: NSManagedObjectID?

    @State private var instruction  = ""
    @State private var step         = 0.0
    @State private var duration     = 0

    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .trailing)]

    // Image Picker
    @State private var isShowingImagePicker = false
    @State private var selectedImageSource  = UIImagePickerController.SourceType.photoLibrary
    @State private var placeHolderImage     = Image(GlobalVariables.noImage)

    var body: some View {
        
        ZStack {
        
            VStack (alignment: .leading) {
 
                // MARK: Buttons
                HStack {
                    Button("Inhalte löschen") {
                        
                        // Clear the form
                        clear()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    //MARK: Public Rezept speichern
                    Button("Public Rezept speichern") {
                        
                        // Add the recipe to firestore or core data
                        updateRecipe(fireStore: true)
                        
                        // Clear the form
                        clear()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    //MARK: Privates Rezept speichern
                    Button("Privates Rezept speichern") {
                        
                        let r: Recipe
                        if let objectId = recipeId,
                           let fetchedRecipe = model.fetchRecipe(for: objectId, context: viewContext) {
                            r = fetchedRecipe
                        } else {
                            r = Recipe(context: viewContext)
                        }
                        
//                        model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipeFB, context: viewContext, recipeImage: recipeImage ?? UIImage())
                  
                        // MARK: Image
                        if let objectId = recipeId {
                            r.image = recipeImage!.jpegData(compressionQuality: 1.0) ?? Data()
                        }
                        else {
                            if recipeFB.id ?? "" > "" {
                                let image     = GlobalVariables.recipesImage[recipeFB.id ?? ""]
                                r.image       = image!.jpegData(compressionQuality: 1.0) ?? Data()
                            }
                            else {
                                r.image       = recipeImage!.jpegData(compressionQuality: 1.0) ?? Data()
                            }
                        }

                        r.name    = recipeFB.name
                        r.summary = recipeFB.summary
                        r.urlLink = recipeFB.urlLink
                        r.rating  = rating
                        r.tags    = recipeFB.tags
                        
                        r.totalWeight = 0
                        for c in r.componentsArray {
                            for i in c.ingredientsArray {
                                r.totalWeight += i.normWeight
                            }
                        }
                        
                        // Save to core data
                        do {
                            // Save the recipe to core data
                            try viewContext.save()
                            
                            // Switch the view to list view
                        }
                        catch {
                            // Couldn't save the recipe
                            print("Couldn't save the recipe")
                        }
                        
                        // Clear the form
                        clear()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    //MARK: Rezept löschen
                    Button("Rezept löschen") {
                        
                        // Delete the recipe on core data
                        
                        let r: Recipe
                        if let objectId = recipeId,
                           let fetchedRecipe = model.fetchRecipe(for: objectId, context: viewContext) {
                            r = fetchedRecipe
                        } else {
                            r = Recipe(context: viewContext)
                        }
                        
                        viewContext.delete(r)
                        
                        // Save to core data
                        do {
                            // Save the recipe to core data
                            try viewContext.save()
                            
                            // Switch the view to list view
                        }
                        catch {
                            // Couldn't save the recipe
                            print("Couldn't save the recipe")
                        }
                        
                        // Clear the form
                        clear()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                                
                NavigationView {
                    
                    ScrollView (showsIndicators: false) {

                        HStack {
                            // MARK: Recipe Image
                            VStack {

                                // Recipe image
                                Image(uiImage: recipeImage ?? UIImage())
                                    .resizable()
                                    .scaledToFill()
                                    .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                                    .cornerRadius(5)
        
                                HStack {
                                    Button("Photo Library") {
                                        selectedImageSource  = .photoLibrary
                                        isShowingImagePicker = true
                                    }
                                    .buttonStyle(.bordered)
        
                                    Text(" | ")
        
                                    Button("Camera") {
                                        selectedImageSource  = .camera
                                        isShowingImagePicker = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                                .sheet(isPresented: $isShowingImagePicker, onDismiss: loadImage) {
                                    ImagePicker(selectedSource: selectedImageSource, recipeImage: $recipeImage)
                                }
                            }
        
                            Spacer()
                            
                            // MARK: Rating Stars
                            RatingStarsUpdateView(rating: $rating)
                                .padding(.trailing)
                        }

                        // The recipe meta data
                        AddMetaData(name:    $recipeFB.name,
                                    summary: $recipeFB.summary,
                                    urlLink: $recipeFB.urlLink)
                    
                        // Tag data
                        AddTagsData(tags: $tags, title: "Tags", placeholderText: "...")
                        
                        RecipeTags(tags: recipeFB.tags)
                        
                        // MARK: Components
                        VStack(alignment: .leading) {
                            
                            Text("Komponenten")
                                .font(Font.custom("Avenir Heavy", size: 16))
                                .padding([.bottom, .top], 5)
                            
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
                                
                                Button("Add") {
                                    
                                    // Make sure that the fields are populated
                                    let cleanedName = componentName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    // Check that all the fields are filled in
                                    if cleanedName == "" { return }
                                    
                                    // Create an ComponentFB object and set its properties
                                    
                                    let recipeCD: Recipe
                                    if let objectId = recipeId,
                                       let fetchedRecipe = model.fetchRecipe(for: objectId, context: viewContext) {
                                        recipeCD = fetchedRecipe
                                    } else {
                                        recipeCD = Recipe(context: viewContext)
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
                                .buttonStyle(.bordered)
                            }
                                
                            if recipeId != nil {
                                EditComponentDataView(recipeId: recipeId!)
                            }
                      
                            Divider()
                            
                            // MARK: Instructions
                            Text("Verarbeitungsschritte")
                                .font(Font.custom("Avenir Heavy", size: 16))
                                .padding([.bottom, .top], 5)
                            
                            LazyVGrid(columns: GlobalVariables.gridItemLayoutInstructions, spacing: 6) {
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
                                
                                Button("Add") {
                                    
                                    // Make sure that the fields are populated
                                    let cleanedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    // Check that all the fields are filled in
                                    if cleanedInstruction == "" { return }
                                    
                                    // Create an ComponentFB object and set its properties
                                    
                                    let recipeCD: Recipe
                                    if let objectId = recipeId,
                                       let fetchedRecipe = model.fetchRecipe(for: objectId, context: viewContext) {
                                        recipeCD = fetchedRecipe
                                    } else {
                                        recipeCD = Recipe(context: viewContext)
                                        return
                                    }

                                    let i         = Instruction(context: viewContext)
                                    i.id          = UUID()
                                    i.instruction = cleanedInstruction
                                    i.step        = step
                                    i.duration    = duration
                                    
                                    recipeCD.addToInstructions(i)
                                }
                                .buttonStyle(.bordered)
                            }
                            
                            if recipeId != nil { EditInstructionDataView(recipeId: recipeId!) }
                        }
                    }
                    .padding()
                }
            }
            .navigationViewStyle(StackNavigationViewStyle()) // full screen mode aktivieren
            .navigationTitle("Rezept bearbeiten")
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
            }
        }
        
    }
    
    // MARK: Load image
    func loadImage() {
        
        // Check if an image was selected from the library
        if recipeImage != nil {
            // Set it as the placeholder image
            placeHolderImage = Image(uiImage: recipeImage!)
        }
    }
    
    // MARK: Clear
    func clear() {
        // Clear all the form fields

        recipeFB    = RecipeFB()
        recipeImage = UIImage()

        placeHolderImage = Image(GlobalVariables.noImage)
    }
    
    // MARK: UpdateRecipe
    func updateRecipe(fireStore: Bool) {

        if fireStore {
            
//            modelFB.recipesFB.append(recipe)
//            modelFB.uploadRecipeToFirestore(r: recipe, i: recipeImage ?? UIImage())
        }
        else {
//            model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipe, context: viewContext, recipeImage: recipeImage ?? UIImage())
        }
    }
}

