//
//  NewEditRecipeView.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 01.01.22.
//

import SwiftUI
import CoreData

struct NewEditRecipeView: View {
    @Environment(\.managedObjectContext) var viewContext
    
    var recipeId: NSManagedObjectID?
    var recipe:   Recipe
    
    @EnvironmentObject var modelFB: RecipeFBModel
    @EnvironmentObject var model:   RecipeModel

    @State private var recipeFB = RecipeFB()
    
    // Recipe Image
    @State private var recipeImage: UIImage?
    @State private var rating        = 0
    @State private var componentName = ""
    @State private var tags          = [String]()
    
    @State private var showingSheet = false
    @State private var selectedComponentId:   NSManagedObjectID?
    @State private var selectedIngredientId:  NSManagedObjectID?
    @State private var selectedInstructionId: NSManagedObjectID?

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
                    
                    Button("Public Rezept speichern") {
                        
                        // Add the recipe to firestore or core data
                        updateRecipe(fireStore: true)
                        
                        // Clear the form
                        clear()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Privates Rezept speichern") {
                        
                        let r: Recipe
                        if let objectId = recipeId,
                           let fetchedRecipe = model.fetchRecipe(for: objectId, context: viewContext) {
                            r = fetchedRecipe
                        } else {
                            r = Recipe(context: viewContext)
                        }
                  
                        // MARK: Image
                        if let objectId = recipeId {
                            r.image       = recipeImage!.jpegData(compressionQuality: 1.0) ?? Data()
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
                        r.rating  = recipeFB.rating ?? 0
                        r.tags    = recipeFB.tags
                        
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
                    
                    Button("Rezept löschen") {
                        
                        // Delete the recipe on core data
//                        deleteRecipe(fireStore: false)
                        
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
                        AddListData(list: $tags, title: "Tags", placeholderText: "...")
                        
                        // MARK: Components
                        VStack(alignment: .leading) {
                            
                            Text("Komponenten")
                                .font(Font.custom("Avenir Heavy", size: 16))
                                .padding([.bottom, .top], 5)
                            
                            HStack {
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
                                        c.number   = recipeCD.components.count
                                        
                                        recipeCD.addToComponents(c)
                                        
                                        componentName = ""
                                    }
                                    .buttonStyle(.bordered)
                                }
                        
                            EditComponentDataView(recipeId: recipeId)
                                

//                // MARK: Instructions
//                VStack(alignment: .leading) {
//                    HStack {
//                        Text("Verarbeitungsschritte:")
//                            .font(Font.custom("Avenir Heavy", size: 16))
//                            .padding([.bottom, .top], 5)
//
//                        Spacer()
//
//                        Text("Bearbeitungdauer: " + Rational.displayHoursMinutes(recipe.prepTime))
//                            .font(Font.custom("Avenir", size: 16))
//                            .padding([.trailing], 5)
//                    }
//
//                    LazyVGrid(columns: gridItemLayout, spacing: 5) {
//                        Text("Schritt").bold()
//                        Text("Beschreibung").bold()
//                        Text("Dauer").bold()
//
//                        ForEach(recipe.instructionsArray, id: \.self) { i in
//
//                            let step = Rational.decimalPlace(i.step, 10)
//                            Text(step)
//                            Text(i.instruction)
//                            Text(Rational.displayHoursMinutes(i.duration))
//                        }
//                        .padding(.horizontal)
//                    }
//                    .font(Font.custom("Avenir", size: 16))
//                        .padding([.bottom, .top], 5)
//                }
                
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
                    let recipe = model.fetchRecipe(for: objectId, context: viewContext)
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
    
    // MARK: load image
    func loadImage() {
        
        // Check if an image was selected from the library
        if recipeImage != nil {
            // Set it as the placeholder image
            placeHolderImage = Image(uiImage: recipeImage!)
        }
    }
    
    // MARK: clear
    func clear() {
        // Clear all the form fields

        recipeFB = RecipeFB()

        placeHolderImage = Image(GlobalVariables.noImage)
    }
    
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

