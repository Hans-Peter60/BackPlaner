//
//  AddRecipeView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import SwiftUI
import CoreData

struct AddRecipeView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel

    // Tab selection
    @Binding var tabSelection: Int
    
    // Properties for recipe meta data
    @State private var name     = ""
    @State private var summary  = ""
    @State private var urlLink  = "https://"
    @State private var prepTime = ""
    @State private var bakeTime = ""
    @State private var servings = ""
    @State private var rating   = 0
    
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
                    
                    Button("In Rezeptdatenbank speichern") {
                        
                        // Add the recipe to firestore or core data
                        addRecipe(fireStore: true)
                        
                        // Clear the form
                        clear()
                        
                        // Navigate to the list
                        tabSelection = GlobalVariables.listTab
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Privates Rezept speichern") {
                        
                        // Add the recipe to firestore or core data
                        addRecipe(fireStore: false)
                        
                        // Clear the form
                        clear()
                        
                        // Navigate to the list
                        tabSelection = GlobalVariables.listTab
                    }
                    .buttonStyle(.bordered)                }
                .padding(.horizontal)
                
                NavigationView {
                    
                    // Scrollview
                    ScrollView (showsIndicators: false) {
                        
                        VStack {
                            Group {
                                HStack {
                                    VStack {
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
                                    }
                                    
                                    Spacer()
                                    
                                    RatingStarsUpdateView(rating: $rating)
                                        .padding(.trailing)
                                }

                                
                                // The recipe meta data
                                AddMetaData(name: $name,
                                            summary: $summary,
                                            urlLink: $urlLink)
                                
                                // Tag data
                                AddListData(list: $tags, title: "Tags", placeholderText: "...")
                                
                                Divider()
                                
                                AddComponentData(components: $components)

                                Divider()
                                
                                AddIngredientData(ingredients: $ingredients, componentsCount: components.count)
                                
                                Divider()
                                
                                // Instruction Data
                                AddInstructionData(instructions: $instructions)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .navigationViewStyle(StackNavigationViewStyle()) // full screen mode aktivieren
                .navigationTitle("Neues Rezept erfassen")
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
        rating       = 0
        tags         = [String]()
        instructions = [InstructionFB]()
        components   = [ComponentFB]()
        ingredients  = [IngredientFB]()
        
        placeHolderImage = Image(GlobalVariables.noImage)
    }
    
    func addRecipe(fireStore: Bool) {
        
        var recipeId: NSManagedObjectID?
        
        // Add the recipe into Firestore
        let recipe             = RecipeFB()
        recipe.id              = ""
        recipe.name            = name
        recipe.summary         = summary
        recipe.urlLink         = urlLink
        recipe.servings        = 1
        recipe.featured        = false
        recipe.rating          = rating
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
            model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipe, context: viewContext, recipeImage: recipeImage ?? UIImage())
        }
    }
}

//struct AddRecipeView_Previews: PreviewProvider {
//    static var previews: some View {
//        AddRecipeView(tabSelection: Binding.constant(GlobalVariables.addRecipeTab))
//    }
//}
