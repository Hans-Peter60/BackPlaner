//
//  BakeHistoryAddView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 23.01.22.
//

import BakePlannerCore
import SwiftUI
import CoreData

struct BakeHistoryAddView: View {
    
    var recipeId: NSManagedObjectID?
    /// The serving factor shown on the page, so the pantry is charged with
    /// what was really used.
    var servingScale: Double = 1
    
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
    /// What the bake takes out of the pantry, offered once the entry is saved.
    @State private var pendingDeductions: [PantryDeduction] = []
    @State private var showingDeductionPrompt = false
    /// Temperatures, proof times, flour, crumb — see BakeHistoryFacts.
    @State private var facts        = BakeHistoryFacts()

    var dateFormat:DateFormat = DateFormat()
    let dateRange: ClosedRange<Date> = GlobalVariables.dateRange(from: DateComponents(year: -10), to: DateComponents(month: 1))
    
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
                            .stroke(Theme.fieldBorder))
                    .font(Theme.bodyFont(16))
                    .frame(minWidth: 200, idealWidth: 300, maxWidth: 600, minHeight: 100, idealHeight: 200, maxHeight: 200, alignment: .center)
                    // A TextEditor has no placeholder to fall back on.
                    .accessibilityLabel("Kommentar")
                
                Spacer()
            }

            BakeHistoryFactsFormSection(facts: $facts)

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
                        // The photo is the link's only content.
                        .accessibilityLabel("Backfoto anzeigen")
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
                bakeHistory.facts   = facts

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
                // The pantry (Pro): what this bake used, to be taken off
                // once the person has seen the entry was saved.
                // A planned bread books its pantry through its plan; only a
                // bread entered without a plan asks here.
                if Entitlements.shared.isUnlocked(.pantry),
                   !BakePlanScheduler.hasPlan(recipeName: recipe.name, in: viewContext),
                   let pantry = try? CoreDataPantryStore(context: viewContext).items(), !pantry.isEmpty {
                    pendingDeductions = PantryMatcher.deductions(for: RecipeExportData(recipe: recipe, includingImage: false),
                                                                 scale: servingScale, pantry: pantry)
                }
            }
            .padding(.trailing)
            .alert("Historie wurde gespeichert", isPresented: $showingAlert) {
                Button("OK", role: .cancel) {
                    if !pendingDeductions.isEmpty { showingDeductionPrompt = true }
                }
            }
            .alert("Vorrat abbuchen?", isPresented: $showingDeductionPrompt) {
                Button("Abbuchen") { applyDeductions() }
                Button("Nicht abbuchen", role: .cancel) { pendingDeductions = [] }
            } message: {
                Text(verbatim: "\(String(localized: "Die verwendeten Mengen werden abgezogen:", locale: AppSettings.locale))\n\(deductionLines)")
            }
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

    /// "Roggenmehl 1150: 1 kg → 700 g", one line per item.
    private var deductionLines: String {
        pendingDeductions.map { deduction in
            var after = deduction.item
            after.amount = deduction.remaining
            return "\(deduction.item.name): \(PantryItemEditorView.amountText(deduction.item)) → \(PantryItemEditorView.amountText(after))"
        }.joined(separator: "\n")
    }

    private func applyDeductions() {
        let store = CoreDataPantryStore(context: viewContext)
        for deduction in pendingDeductions {
            var item = deduction.item
            item.amount = deduction.remaining
            try? store.update(item)
        }
        pendingDeductions = []
    }
}
