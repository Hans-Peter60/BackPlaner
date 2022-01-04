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
    @State private var recipe = RecipeFB()
    
    @State private var name            = ""
    @State private var summary         = ""
    @State private var urlLink         = ""
    @State private var prepTime        = 0
    @State private var rating          = 0
    @State private var bakeHistoryFlag = false

    
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
                        clear()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Public Rezept speichern") {
                        
                        // Add the recipe to firestore or core data
                        updateRecipe(fireStore: true)
                        
                        // Clear the form
                        clear()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Privates Rezept speichern") {
                        
                        // Add the recipe to firestore or core data
                        updateRecipe(fireStore: false)
                        
                        // Clear the form
                        clear()
                    }
                    .buttonStyle(.bordered)

                }
                .padding(.horizontal)
                
                NavigationView {
                    
                    // Scrollview
                    ScrollView (showsIndicators: false) {
                        
                        VStack {
                            Group {
                                
                                HStack {
                                    VStack {
                                
                                        // Recipe image
                                        Image(uiImage: recipeImage ?? UIImage())
                                            .resizable()
                                            .scaledToFill()
                                            .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                                            .cornerRadius(5)
                                        
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
                                    }
                                    
                                    Spacer()
                                    
                                    RatingStarsUpdateView(rating: $rating)
                                        .padding(.trailing)
                                }
                                
                                // The recipe meta data
                                AddMetaData(name:    $recipe.name,
                                            summary: $recipe.summary,
                                            urlLink: $recipe.urlLink)
                                
                                // Tag data
                                AddListData(list: $recipe.tags, title: "Tags", placeholderText: "Sauerteig")
                                
                                Divider()
                                
                                // Component & Ingredient Data
                                AddComponentData(components: $recipe.components)
                                
                                Divider()
                                
                                // Instruction Data
                                EditInstructionData(instructions: $recipe.instructions)
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
                        let recipeCD = model.fetchRecipe(for: objectId, context: viewContext)
                    else {
                        return
                    }
                    
                    clear()
                    
                    recipe.name            = recipeCD.name
                    recipe.summary         = recipeCD.summary
                    recipe.urlLink         = recipeCD.urlLink ?? ""
                    recipe.rating          = recipeCD.rating
                    recipe.bakeHistoryFlag = recipeCD.bakeHistoryFlag
                    recipe.tags            = recipeCD.tags
                    recipeImage            = UIImage(data: recipeCD.image) ?? UIImage()
                    recipe.prepTime        = recipeCD.prepTime
                    
                    for i in recipeCD.instructionsArray {
                        let instruction = InstructionFB()
                        
                        instruction.id          = "old" + UUID().uuidString
                        instruction.instruction = i.instruction
                        instruction.step        = i.step
                        instruction.duration    = i.duration
                        instruction.startTime   = i.startTime
                        
                        // Add this instruction to the recipe
                        recipe.instructions.append(instruction)
                    }

                    for comp in recipeCD.componentsArray {
                        let cFB = ComponentFB()
                        
                        cFB.id     = "old" + UUID().uuidString
                        cFB.name   = comp.name
                        cFB.number = comp.number
                        
                        // Add the ingredients
                        for ingred in comp.ingredientsArray {
            
                            let iFB = IngredientFB()
                            
                            iFB.id          = "old" + UUID().uuidString
                            iFB.number      = ingred.number
                            iFB.name        = ingred.name
                            iFB.denom       = ingred.denom
                            iFB.num         = ingred.num
                            iFB.unit        = ingred.unit ?? ""
                            iFB.weight      = ingred.weight
                            
                            cFB.ingredients.append(iFB)
                        }
                        recipe.components.append(cFB)
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
        
        recipe = RecipeFB()

        placeHolderImage = Image(GlobalVariables.noImage)
    }
    
    func updateRecipe(fireStore: Bool) {

//        // Add the recipe into Firestore or CoreData
//        let recipe             = RecipeFB()
//        recipe.id              = ""
//        recipe.name            = name
//        recipe.summary         = summary
//        recipe.urlLink         = urlLink
//        recipe.rating          = rating
//        recipe.bakeHistoryFlag = bakeHistoryFlag
//        recipe.tags            = tags
//
//        for i in instructions {
//
//            if i.id!.contains("old") {
//            }
//            else {
//                let instruction = InstructionFB()
//
//                instruction.instruction = i.instruction
//                instruction.step        = i.step
//                instruction.duration    = i.duration
//                instruction.startTime   = 0
//
//                // Add this instruction to the recipe
//                recipe.instructions.append(instruction)
//            }
//        }
//        recipe.instructions = Rational.calculateStartTimes(recipe.instructions, Date())
//        recipe.prepTime = GlobalVariables.totalDuration
//
//        for c in components {
//
//            if c.id!.contains("old") {
//            }
//            else {
//                // Add the ingredients
//                for i in ingredients {
//
//                    if i.id!.contains("old") {
//                    }
//                    else {
//
//                        if i.componentNr == c.number {
//
//                            c.ingredients.append(i)
//                        }
//                    }
//                }
//                recipe.components.append(c)
//            }
//        }

        if fireStore {
            
            modelFB.recipesFB.append(recipe)
            modelFB.uploadRecipeToFirestore(r: recipe, i: recipeImage ?? UIImage())
        }
        else {
            model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipe, context: viewContext, recipeImage: recipeImage ?? UIImage())
        }
    }
}

