//
//  BakeHistoryUpdateFormView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 14.12.21.
//

import SwiftUI
import CoreData

struct BakeHistoryUpdateFormView: View {
    
    var recipeName: String
    var bakeHistory: BakeHistory
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var model: RecipeModel
    
    var dateFormat:DateFormat = DateFormat()
    
    // Image Picker
    @State private var isShowingImagePicker = false
    @State private var selectedImageSource  = UIImagePickerController.SourceType.photoLibrary
    @State private var placeHolderImage     = Image(systemName: "photo")
    
    // BakeHistory Images
    @State private var recipeImage:   UIImage?
    @State private var comment      = ""
    @State private var recipeImages = [UIImage?]()
    @State private var images       = [Data]()
    @State private var showingAlert = false

    var body: some View {
        
        Form {
                  
            Text(recipeName)
                .font(Theme.brandFont(18))

            TextEditor(text: $comment)
                .multilineTextAlignment(.leading)
                .padding(4)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray).opacity(0.3))
                .font(Theme.bodyFont(16))
                .frame(minWidth: 200, idealWidth: 300, maxWidth: 600, minHeight: 100, idealHeight: 200, maxHeight: 200, alignment: .center)
                
            Section {
                
                HStack {
                    // Recipe bakeHistory images
                    ForEach(recipeImages, id: \.self) { rI in
                        
                        NavigationLink(
                            destination: ShowBigImageView(image: rI?.jpegData(compressionQuality: 1.0) ?? Data())
                        )
                        {
                            Image(uiImage: rI ?? UIImage())
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50, alignment: .center)
                                .clipped()
                                .cornerRadius(5)
                        }
                    }
                }
                
                HStack {
                    IconActionButton(systemImage: "photo.on.rectangle", style: .primary, accessibilityLabel: "Fotomediathek öffnen", title: "Fotomediathek", controlSize: .regular) {
                        selectedImageSource = .photoLibrary
                        isShowingImagePicker = true
                    }
                    .padding(.trailing)

                }
                .sheet(isPresented: $isShowingImagePicker, onDismiss: loadImage) {
                    ImageArrayPicker(selectedSource: selectedImageSource, recipeImages: $recipeImages)
                }
            }
                
            IconActionButton(systemImage: "checkmark", style: .primary, accessibilityLabel: "Historie speichern", title: "Speichern", controlSize: .regular) {
                
                bakeHistory.setValue(comment, forKey: "comment")
                
                images = [Data]()
                for index in 0..<recipeImages.count {
                    images.append(recipeImages[index]?.jpegData(compressionQuality: 1.0) ?? Data())
                }
                bakeHistory.setValue(images, forKey: "images")
                showingAlert = true
                
                do {
                    try viewContext.save()
                } catch {
                    // handle the Core Data error
                    showingAlert = false
                }
            }
            .padding(.trailing)
            .alert("Historie wurde gespeichert", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { } }
        }
        .clearScrollBackground()
        .warmBackground()
        .navigationTitle("Backanmerkungen- / hinweise")
        .onAppear {
            comment = self.bakeHistory.comment
            images  = self.bakeHistory.images ?? [Data]()
            recipeImages = [UIImage]()
            
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
