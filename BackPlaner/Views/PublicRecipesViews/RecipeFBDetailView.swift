//
//  RecipeFBDetailView.swift
//  PetersBackPlaner
//
//  Created by Hans-Peter Müller on 23.11.21.
//

import SwiftUI
import CoreData

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
    // Error message shown when releasing a reported recipe fails.
    @State private var releaseErrorMessage: String?

    var gridItemLayout = [GridItem(scaledColumnSize(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(scaledColumnSize(100), alignment: .trailing)]
    
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
                        // The image is the link's only content, so without this the
                        // link would be announced with no name at all.
                        .accessibilityLabel("Rezeptbild vergrößern")
                        
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
                            ServingSizePicker(selection: $selectedServingSize)
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
                    ComponentColumnsView(components: ComponentColumn.columns(of: recipeFB.components),
                                         selectedServingSize: selectedServingSize)

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
                        .scrollsSidewaysAtLargeText()
                        .font(Theme.bodyFont(16))
                        .padding([.bottom, .top], 5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()

                    // MARK: Admin/owner moderation — review reported recipes and
                    // delete ANY public recipe.
                    if modelFB.isAdmin {
                        if recipeFB.hidden {
                            Text("Dieses Rezept wurde gemeldet und ist für alle anderen Nutzer ausgeblendet.")
                                .font(.footnote)
                                .foregroundColor(Theme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top)

                            IconActionButton(systemImage: "eye", style: .primary, accessibilityLabel: "Rezept wieder freigeben", title: "Rezept wieder freigeben", controlSize: .regular) {
                                modelFB.setRecipeHidden(recipeFB, hidden: false) { result in
                                    if case .failure(let error) = result {
                                        releaseErrorMessage = error.localizedDescription
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

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
            .alert("Freigeben fehlgeschlagen", isPresented: Binding(
                get: { releaseErrorMessage != nil },
                set: { if !$0 { releaseErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { releaseErrorMessage = nil }
            } message: {
                Text(releaseErrorMessage ?? "")
            }
        }
    }
}
