//
//  BakeHistoryUpdateForm.swift
//  BackPlaner
//
//  Created by Hans-Peter Müller on 14.12.21.
//

import SwiftUI

struct BakeHistoryUpdateForm: View {
    
    var recipe: Recipe
    var bakeHistory: BakeHistory
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var model: RecipeModel
    
    // Image Picker
    @State private var isShowingImagePicker = false
    @State private var selectedImageSource  = UIImagePickerController.SourceType.photoLibrary
    @State private var placeHolderImage     = Image("no-image-icon-23494")
    
    // BakeHistory Images
    @State private var recipeImage:   UIImage?
    @State private var comment      = ""
    @State private var recipeImages = [UIImage?]()
    @State private var images       = [Data]()

    var body: some View {
        Text(recipe.name)
            .font(Font.custom("Avenir Heavy", size: 20))

        ScrollView {
        VStack {
            
            VStack {
                Text("Kommentar: ")
                    .bold()
                    .padding([.leading, .trailing])
                
                TextEditor(text: $comment)
                    .multilineTextAlignment(.leading)
                    .border(/*@START_MENU_TOKEN@*/Color.black/*@END_MENU_TOKEN@*/, width: /*@START_MENU_TOKEN@*/1/*@END_MENU_TOKEN@*/)
                    .frame(minWidth: 200, idealWidth: 300, maxWidth: 600, minHeight: 100, idealHeight: 200, maxHeight: 200, alignment: .center)
                    .padding(.leading)
                    .cornerRadius(/*@START_MENU_TOKEN@*/3.0/*@END_MENU_TOKEN@*/)
            }
            
            VStack {
                // Recipe bakeHistory images
                ForEach(0..<recipeImages.count) { index in
                    
                    Image(uiImage: recipeImages[index] ?? UIImage())
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50, alignment: .center)
                        .clipped()
                        .cornerRadius(5)
                }
            }
            
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
                ImageArrayPicker(selectedSource: selectedImageSource, recipeImages: $recipeImages)
            }
            
            Button("Speichern") {

                bakeHistory.setValue(comment, forKey: "comment")
                
                for index in 0..<recipeImages.count {
                    images.append(recipeImages[index]!.jpegData(compressionQuality: 1.0) ?? Data())
                }
                bakeHistory.setValue(images, forKey: "images")

                do {
                    try viewContext.save()
                } catch {
                    // handle the Core Data error
                }
            }
            .font(Font.custom("Avenir", size: 15))
            .padding(.trailing)
            .foregroundColor(.gray)
            .buttonStyle(.bordered)
        }
        .navigationTitle("Backanmerkungen- / hinweise")
        }
        .onAppear {
            comment = self.bakeHistory.comment
            images  = self.bakeHistory.images
            for index in 0..<images.count {
                recipeImages.append(UIImage(data: images[index]) ?? UIImage())
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
}

//struct BakeHistoryUpdateForm_Previews: PreviewProvider {
//    static var previews: some View {
//        BakeHistoryUpdateForm()
//    }
//}