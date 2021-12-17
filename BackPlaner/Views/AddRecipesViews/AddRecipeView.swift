//
//  AddRecipeView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 09.11.21.
//

import SwiftUI

struct AddRecipeView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model: RecipeModel

    // Tab selection
    @Binding var tabSelection: Int
    
    // Properties for recipe meta data
    @State private var name = ""
    @State private var summary = ""
    @State private var urlLink = ""
    @State private var prepTime = ""
    @State private var bakeTime = ""
    @State private var servings = ""
    
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
    @State private var placeHolderImage     = Image("no-image-icon-23494")
    
    var body: some View {
        ZStack {
            Text("")
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .background(Color.white)
                .edgesIgnoringSafeArea(.all)
            
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
                                // Recipe image
                                placeHolderImage
                                    .resizable()
                                    .scaledToFit()
                                    .frame(minWidth: 100, idealWidth: 200, maxWidth: 200, minHeight: 100, idealHeight: 200, maxHeight: 200, alignment: .center)
                                
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
        
        placeHolderImage = Image("no-image-icon-23494")
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
                if i.component == c.id {

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
            model.uploadRecipeIntoCoreData(recipeFB: recipe)
        }
    }
}

//struct AddRecipeView_Previews: PreviewProvider {
//    static var previews: some View {
//        AddRecipeView(tabSelection: Binding.constant(GlobalVariables.addRecipeTab))
//    }
//}
