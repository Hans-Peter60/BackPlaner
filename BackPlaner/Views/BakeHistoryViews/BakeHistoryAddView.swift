//
//  BakeHistoryAddView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 23.01.22.
//

import SwiftUI
import CoreData

struct BakeHistoryAddView: View {
    
    var recipeId: NSManagedObjectID?
    
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var model: RecipeModel
    
    // Image Picker
    @State private var isShowingImagePicker = false
    @State private var selectedImageSource  = UIImagePickerController.SourceType.photoLibrary
    @State private var placeHolderImage     = Image(systemName: "photo")
    
    // BakeHistory Images
    @State private var recipeImage:   UIImage?
    @State private var recipeName   = ""
    @State private var comment      = ""
    @State private var recipeImages = [UIImage?]()
    @State private var images       = [Data]()
    @State private var date         = GlobalVariables.dateTimePicker
    @State private var showingAlert = false
    
    var dateFormat:DateFormat = DateFormat()
    let dateRange: ClosedRange<Date> = {
        let calendar = Calendar.current
        let startComponents = DateComponents(year: GlobalVariables.year! - 10, month: GlobalVariables.month, day: GlobalVariables.day)
        let endComponents   = DateComponents(year: GlobalVariables.year, month: GlobalVariables.month! + 1, day: GlobalVariables.day)
        return calendar.date(from:startComponents)!
        ...
        calendar.date(from:endComponents)!
    }()
    
    var body: some View {
        
        Form {
                  
            Text(recipeName)
                .font(Theme.brandFont(18))

            HStack {
                
                VStack(alignment: .leading) {
                    
                    DatePicker(
                        "Backdatum",
                        selection: $date,
                        in: dateRange,
                        displayedComponents: [.date]
                    )
                        .padding()
                        .environment(\.locale, AppSettings.locale)
                    
                    Spacer()
                }

                TextEditor(text: $comment)
                    .multilineTextAlignment(.leading)
                    .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray).opacity(0.3))
                    .font(Theme.bodyFont(16))
                    .frame(minWidth: 200, idealWidth: 300, maxWidth: 600, minHeight: 100, idealHeight: 200, maxHeight: 200, alignment: .center)
                
                Spacer()
            }
            
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
                        selectedImageSource  = .photoLibrary
                        isShowingImagePicker = true
                    }
                    .padding(.trailing)

                }
                .sheet(isPresented: $isShowingImagePicker, onDismiss: loadImage) {
                    ImageArrayPicker(selectedSource: selectedImageSource, recipeImages: $recipeImages)
                }
            }
                
            IconActionButton(systemImage: "checkmark", style: .primary, accessibilityLabel: "Historie speichern", title: "Speichern", controlSize: .regular) {
            
                guard
                    let objectId = recipeId,
                    let recipe   = model.fetchRecipe(for: objectId, context: viewContext)
                else {
                    return
                }
                
                let bakeHistory     = BakeHistory(context: viewContext)
                bakeHistory.id      = UUID()
                bakeHistory.date    = date
                bakeHistory.comment = comment
                
                images = [Data]()
                for index in 0..<recipeImages.count {
                    images.append(recipeImages[index]?.jpegData(compressionQuality: 1.0) ?? Data())
                }
                bakeHistory.images = images

                recipe.bakeHistoryFlag = true
                recipe.addToBakeHistories(bakeHistory)
                
                showingAlert = true
                GlobalVariables.dateTimePicker = date
                
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

            guard
                let objectId = recipeId,
                let recipe   = model.fetchRecipe(for: objectId, context: viewContext)
            else {
                return
            }
            recipeName = recipe.name
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
