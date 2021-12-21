//
//  EditRecipeView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 21.12.21.
//

import SwiftUI
import CoreData

struct EditRecipeView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel
    
    var recipeId: NSManagedObjectID?
    
    // Properties for recipe meta data
    @State private var name     = ""
    @State private var summary  = ""
    @State private var urlLink  = ""
    @State private var prepTime = 0
    @State private var featured = false
    @State private var servings = 1
    
    // List type recipe meta data
    @State private var tags = [String]()
    
    @State private var instructions = [InstructionFB]()
    
    // Component & Ingredient data
    @State private var componentId = "1"
    @State private var components = [ComponentFB]()
    @State private var componentName = ""
    @State private var ingredients = [IngredientFB]()
    
    // Recipe Image
    @State private var recipeImage: UIImage?
    
    // Image Picker
    @State private var isShowingImagePicker = false
    @State private var selectedImageSource  = UIImagePickerController.SourceType.photoLibrary
    @State private var placeHolderImage     = Image(GlobalVariables.noImage)
    
    var body: some View {
        ZStack {
            
            VStack {
                // HStack with the form controls
                HStack {
                    Button("Inhalte löschen") {
                        
                        // Clear the form
//                        clear()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Public Rezept speichern") {
                        
                        // Add the recipe to firestore or core data
                        addRecipe(fireStore: true)
                        
                        // Clear the form
//                        clear()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Privates Rezept speichern") {
                        
                        // Add the recipe to firestore or core data
                        addRecipe(fireStore: false)
                        
                        // Clear the form
//                        clear()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                
                NavigationView {
                    
                    // Scrollview
                    ScrollView (showsIndicators: false) {
                        
                        VStack {
                            Group {
                                // Recipe image
                                placeHolderImage
                                    .resizable()
                                    .scaledToFit()
                                    .frame(minWidth: 50, idealWidth: 100, maxWidth: 150, minHeight: 50, idealHeight: 100, maxHeight: 150, alignment: .center)
                                
                                HStack {
                                    Button("Photo Library") {
                                        selectedImageSource = .photoLibrary
                                        isShowingImagePicker = true
                                    }
                                    
                                    Text(" | ")
                                    
                                    Button("Camera") {
                                        selectedImageSource = .camera
                                        isShowingImagePicker = true
                                    }
                                }
                                .sheet(isPresented: $isShowingImagePicker, onDismiss: loadImage) {
                                    ImagePicker(selectedSource: selectedImageSource, recipeImage: $recipeImage)
                                }
                                
                                // The recipe meta data
                                AddMetaData(name: $name,
                                            summary: $summary,
                                            urlLink: $urlLink)
                                
                                // Tag data
                                AddListData(list: $tags, title: "Tags", placeholderText: "Sauerteig")
                                
                                Divider()
                                
                                AddComponentData(components: $components)
                                
                                Divider()
                                
                                AddIngredientData(ingredients: $ingredients)
                                
                                Divider()
                                
                                // Instruction Data
                                AddInstructionData(instructions: $instructions)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .navigationViewStyle(StackNavigationViewStyle()) // full screen mode aktivieren
                .navigationTitle("Rezept bearbeiten")
                .onAppear {
                    guard
                        let objectId = recipeId,
                        let recipe   = model.fetchRecipe(for: objectId, context: viewContext)
                    else {
                        return
                    }
                    
                    name     = recipe.name
                    summary  = recipe.summary
                    urlLink  = recipe.urlLink ?? ""
                    servings = recipe.servings
                    featured = recipe.featured
                    tags     = recipe.tags
                    
                    for i in recipe.instructionsArray {
                        let instruction = InstructionFB()
                        
                        instruction.id          = UUID().uuidString
                        instruction.instruction = i.instruction
                        instruction.step        = i.step
                        instruction.duration    = i.duration
                        instruction.startTime   = i.startTime
                        
                        // Add this instruction to the recipe
                        instructions.append(instruction)
                    }

                    prepTime = recipe.prepTime
                    
                    var componentNumber = 1
                    
                    for comp in recipe.components {
                        let c   = comp as! Component
                        let cFB = ComponentFB()
                        
                        cFB.id     = UUID().uuidString
                        cFB.name   = c.name
                        cFB.number = c.number
                        
                        // Add the ingredients
                        for ingred in c.ingredients {
                            let i   = ingred as! Ingredient
                            let iFB = IngredientFB()
                            
                            iFB.id          = UUID().uuidString
                            iFB.componentNr = componentNumber
                            iFB.number      = i.number
                            iFB.name        = i.name
                            iFB.denom       = i.denom
                            iFB.num         = i.num
                            iFB.unit        = i.unit
                            iFB.weight      = i.weight
                            
                            ingredients.append(iFB)
                        }
                        components.append(cFB)
                        componentNumber += 1
                    }
                }
            }
        }
    }
    
    func loadImage() {
        
        // Check if an image was selected from the library
        if recipeImage != nil {
            // Set it as the placeholder image
            placeHolderImage = Image(uiImage: recipeImage!)
        }
    }
    
    func clear() {
        // Clear all the form fields
        name         = ""
        summary      = ""
        urlLink      = ""
        tags         = [String]()
        instructions = [InstructionFB]()
        components   = [ComponentFB]()
        ingredients  = [IngredientFB]()

        placeHolderImage = Image(GlobalVariables.noImage)
    }
    
    func addRecipe(fireStore: Bool) {
        
        // Add the recipe into Firestore
        let recipe             = RecipeFB()
        recipe.id              = ""
        recipe.name            = name
        recipe.summary         = summary
        recipe.urlLink         = urlLink
        recipe.servings        = 1
        recipe.featured        = false
        recipe.bakeHistoryFlag = false
        recipe.tags            = tags
        
        for i in instructions {
            let instruction = InstructionFB()
            
            instruction.instruction = i.instruction
            instruction.step        = i.step
            instruction.duration    = i.duration
            instruction.startTime   = 0
            
            // Add this instruction to the recipe
            recipe.instructions.append(instruction)
        }
        recipe.instructions = Rational.calculateStartTimes(recipe.instructions, Date())
        recipe.prepTime = GlobalVariables.totalDuration
        
        for c in components {
            
            // Add the ingredients
            for i in ingredients {
                if i.componentNr == c.number {
                    
                    c.ingredients.append(i)
                }
            }
            recipe.components.append(c)
        }
        
        modelFB.recipesFB.append(recipe)
        
        if fireStore {
            modelFB.uploadRecipeToFirestore(r: recipe, i: recipeImage ?? UIImage())
        }
        else {
            model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipe, context: viewContext)
        }
    }
}

