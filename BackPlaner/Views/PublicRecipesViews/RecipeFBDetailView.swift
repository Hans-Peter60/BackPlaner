//
//  RecipeFBDetailView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 23.11.21.
//

import SwiftUI

struct RecipeFBDetailView: View {

    var recipeFB:RecipeFB

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var modelFB: RecipeFBModel

    @State private var totalWeight = 0.0
    @State var selectedServingSize = AppSettings.storedServingSize
    // Admin/owner moderation: confirm before deleting any public recipe.
    @State private var showAdminDeleteConfirm = false
    // Error message shown when a delete fails (e.g. Firestore rules deny it), so
    // the screen no longer silently dismisses as if it had worked.
    @State private var deleteErrorMessage: String?

    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .trailing)]
    
    var body: some View {
        
        GeometryReader { fullView in
            
            ScrollView(.vertical, showsIndicators: false) {
                
                VStack (alignment: .leading) {
                                    
                    HStack {
                        
                        // MARK: Recipe image
                        NavigationLink(
                            destination: ShowBigImageView(image: (GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage()).jpegData(compressionQuality: 1.0) ?? Data() )
                        )
                        {
                            Image(uiImage: GlobalVariables.recipesImage[recipeFB.id ?? ""] ?? UIImage())
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                                .cornerRadius(5)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(recipeFB.name)
                                .font(Theme.brandFont(18))
                                .foregroundColor(Theme.title)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            // MARK: Recipe summary
                            Text(recipeFB.summary)
                                .font(Theme.bodyFont(15))
                        }
                            .padding(.leading, 4)
                    }
                    
                    HStack {
                        // MARK: Serving size picker
                        PortraitAdaptiveStack(spacing: 6) {
                            Text("Portionsgröße")
                                .font(Theme.bodyFont(15))
                            Picker("", selection: $selectedServingSize) {
                                Text(0.5, format: .number.precision(.fractionLength(1))).tag(1)
                                Text(1.0, format: .number.precision(.fractionLength(1))).tag(2)
                                Text(1.5, format: .number.precision(.fractionLength(1))).tag(3)
                                Text(2.0, format: .number.precision(.fractionLength(1))).tag(4)
                            }
                            .font(Theme.bodyFont(15))
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width:160)
                        }
                        
                        Spacer()
                        
                        Text("Gewicht: \(Int((recipeFB.totalWeight) * Double(selectedServingSize) / 2.0), format: .number) g")
                            .font(Theme.bodyFont(15))
                        
                        Spacer()
                        
                        // MARK: Recipe urlLink
                        if let url = URL(string: recipeFB.urlLink) {
                            Link("Link zum Rezept", destination: url)
                                .padding(.top, 2)
                                .padding(.leading)
                                .font(Theme.brandFont(15))
                        }
                    }
                    
                    TotalIngredientsView(
                        ingredients: recipeFB.components.flatMap(\.ingredients).map {
                            TotalIngredientData(
                                name: $0.name,
                                unit: $0.unit,
                                weight: $0.weight,
                                numerator: $0.num,
                                denominator: $0.denom
                            )
                        },
                        componentNames: recipeFB.components.map(\.name),
                        selectedServingSize: selectedServingSize
                    )

                    // MARK: Components
                    Section {
                        VStack(alignment: .leading) {
                            
                            LazyVGrid(columns: GlobalVariables.gridItemLayoutComponents, spacing: 6) {
                                
                                ForEach (recipeFB.components.sorted(by: { $0.number < $1.number })) { item in
                                    
                                    VStack(alignment: .leading) {
                                        
                                        Text(item.name)
                                            .font(Theme.brandFont(14))
                                            .padding([.bottom, .top], 5)
                                        
                                        // MARK: Ingredients
                                        VStack(alignment: .leading) {
                                            ForEach (item.ingredients.sorted(by: { $0.number < $1.number })) { ingred in
                                                
                                                let t = "• " + Rational.getPortion(unit:ingred.unit, weight:ingred.weight, num:ingred.num, denom:ingred.denom, targetServings: selectedServingSize)
                                                Text(t + ingred.name)
                                                    .font(Theme.bodyFont(15))
                                            }
                                        }                            }
                                }
                            }
                        }
                    } header: {
                        Text("Komponenten:")
                            .font(Theme.brandFont(16))
                            .foregroundColor(Theme.title)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()


                    Divider()
                    
                    // MARK: Instructions
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Verarbeitungsschritte:")
                                .font(Theme.brandFont(16))
                                .foregroundColor(Theme.title)
                                .padding([.bottom, .top], 5)
                            
                            Spacer()
                            
                            Text("Bearbeitungsdauer: " + Rational.displayHoursMinutes(recipeFB.prepTime))
                                .font(Theme.bodyFont(16))
                                .padding([.trailing], 5)
                        }
                        
                        LazyVGrid(columns: gridItemLayout, spacing: 5) {
                            Text("Schritt").bold()
                            Text("Beschreibung").bold()
                            Text("Dauer").bold()
                            
                            ForEach(recipeFB.instructions.sorted(by: { $0.step < $1.step })) { i in
                                
                                let step = Rational.decimalPlace(i.step, 10)
                                Text(step)
                                Text(i.instruction)
                                Text(Rational.displayHoursMinutes(i.duration))
                            }
                        }
                        .font(Theme.bodyFont(16))
                        .padding([.bottom, .top], 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    // MARK: Admin/owner moderation — delete ANY public recipe.
                    if modelFB.isAdmin {
                        IconActionButton(systemImage: "trash", style: .destructive, accessibilityLabel: "Rezept löschen (Admin)", title: "Rezept löschen (Admin)", controlSize: .regular) {
                            showAdminDeleteConfirm = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top)
                    }
                }
                .padding()
            }
            .warmBackground()
            .navigationTitle(Text(recipeFB.name))
            .confirmationDialog("Öffentliches Rezept löschen?", isPresented: $showAdminDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    modelFB.deleteRecipeAsAdmin(recipeFB) { result in
                        switch result {
                        case .success:
                            dismiss()
                        case .failure(let error):
                            deleteErrorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Dieses Rezept wird als Administrator endgültig aus der öffentlichen Datenbank entfernt.")
            }
            .alert("Löschen fehlgeschlagen", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
        }
    }
}
