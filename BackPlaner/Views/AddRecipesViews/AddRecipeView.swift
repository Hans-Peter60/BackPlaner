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

    @State private var recipeFB = RecipeFB()
    
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
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Button("Privates Rezept speichern") {
                        
                        // Add the recipe to firestore or core data
                        addRecipe(fireStore: false)
                        
                        // Clear the form
                        clear()
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
                                                selectedImageSource  = .photoLibrary
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
                                    
                                    RatingStarsUpdateView(rating: $recipeFB.rating)
                                        .padding(.trailing)
                                }
                                
                                // The recipe meta data
                                AddMetaData(name:    $recipeFB.name,
                                            summary: $recipeFB.summary,
                                            urlLink: $recipeFB.urlLink)
                                
                                // Tag data
                                AddTagsData(tags: $recipeFB.tags, title: "Tags", placeholderText: "...")
                                
                                Divider()
                                
                                AddComponentData(components: $recipeFB.components)
                                
                                Divider()
                                
                                // Instruction Data
                                AddInstructionData(instructions: $recipeFB.instructions)
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
        
        recipeFB = RecipeFB()
        
        placeHolderImage = Image(GlobalVariables.noImage)
    }
    
    func addRecipe(fireStore: Bool) {
        
        var recipeId: NSManagedObjectID?
        
        if fireStore {
            modelFB.uploadRecipeToFirestore(r: recipeFB, i: recipeImage ?? UIImage())
        }
        else {
            model.uploadRecipeIntoCoreData(recipeId: recipeId, recipeFB: recipeFB, context: viewContext, recipeImage: recipeImage ?? UIImage())
        }
    }
}

