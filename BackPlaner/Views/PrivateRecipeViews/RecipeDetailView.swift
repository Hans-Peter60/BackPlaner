//
//  RecipeDetailView.swift
//  PetersBackPlaner App
//
//  Created by Hans-Peter Müller on 2021-01-14.
//

import SwiftUI

struct RecipeDetailView: View {
    
//    @Environment(\.presentationMode) var presentationMode
    
    var recipe:Recipe
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .trailing)]

    @State var selectedServingSize = AppSettings.storedServingSize
    
    var body: some View {
        
        ScrollView {
        
            VStack (alignment: .leading) {
                
                HStack {
                    // MARK: Recipe Image
                    NavigationLink(
                        destination: ShowBigImageView(image: recipe.image)
                    )
                    {
                        let image = UIImage(data: recipe.image) ?? UIImage()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                            .cornerRadius(5)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(recipe.name)
                            .font(Theme.brandFont(18))
                            .foregroundColor(Theme.title)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bewertung")
                                .font(Theme.brandFont(16))
                                .foregroundColor(Theme.title)

                            RatingStarsView(rating: recipe.rating, label: "")
                                .font(.title3)
                        }
                    }
                    .padding(.leading, 4)

                    Spacer(minLength: 8)
                }

                
                // MARK: Recipe summary
                Text(recipe.summary)
                    .padding(.top, 2)
                    .font(Theme.bodyFont(15))
                    
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
                    
                    Text("Gewicht: \(Int(recipe.totalWeight * Double(selectedServingSize) / 2.0), format: .number) g")
                            .font(Theme.bodyFont(15))
                    
                    Spacer()
                    
                    // MARK: Recipe urlLink
                    if let url = URL(string: recipe.urlLink ?? "") {
                        Link("Link zum Rezept", destination: url)
                            .padding(.top, 2)
                            .padding(.leading)
                            .font(Theme.brandFont(15))
                    }
                }
                
                TotalIngredientsView(
                    ingredients: recipe.componentsArray.flatMap(\.ingredientsArray).map {
                        TotalIngredientData(
                            name: $0.name,
                            unit: $0.unit ?? "",
                            weight: $0.weight,
                            numerator: $0.num,
                            denominator: $0.denom
                        )
                    },
                    componentNames: recipe.componentsArray.map(\.name),
                    selectedServingSize: selectedServingSize
                )

                // MARK: Components
                VStack(alignment: .leading) {
                    Text("Komponenten")
                        .font(Theme.brandFont(16))
                        .foregroundColor(Theme.title)
                        .padding([.bottom, .top], 5)

                    LazyVGrid(columns: GlobalVariables.gridItemLayoutComponents, spacing: 6) {

                        ForEach (recipe.componentsArray.sorted(by: { $0.number < $1.number })) { component in
                            
                            VStack(alignment: .leading) {
                                
                                Text(component.name)
                                    .font(Theme.brandFont(14))
                                    .padding([.bottom, .top], 5)
                                
                                VStack(alignment: .leading) {

                                    ForEach (component.ingredientsArray.sorted(by: { $0.number < $1.number })) { item in

                                        Text("• " + Rational.getPortion(unit:item.unit ?? "", weight:item.weight, num:item.num, denom:item.denom, targetServings: selectedServingSize) + item.name)
                                            .font(Theme.bodyFont(15))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()


                // MARK: Instructions
                VStack(alignment: .leading) {
                    HStack {
                        Text("Verarbeitungsschritte:")
                            .font(Theme.brandFont(16))
                            .foregroundColor(Theme.title)
                            .padding([.bottom, .top], 5)
                        
                        Spacer()
                        
                        Text("Bearbeitungsdauer: " + Rational.displayHoursMinutes(recipe.prepTime))
                            .font(Theme.bodyFont(16))
                            .padding([.trailing], 5)
                    }
 
                    LazyVGrid(columns: gridItemLayout, spacing: 5) {
                        Text("Schritt").bold()
                        Text("Beschreibung").bold()
                        Text("Dauer").bold()
                      
                        ForEach(recipe.instructionsArray, id: \.self) { i in
                            
                            let step = Rational.decimalPlace(i.step, 10)
                            Text(step)
                            Text(i.instruction)
                            Text(Rational.displayHoursMinutes(i.duration))
                        }
                        .padding(.horizontal)
                    }
                    .font(Theme.bodyFont(16))
                        .padding([.bottom, .top], 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding()
        }
        .warmBackground()
        .navigationTitle(recipe.name)

    }
}
