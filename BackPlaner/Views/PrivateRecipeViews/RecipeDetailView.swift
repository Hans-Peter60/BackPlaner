//
//  RecipeDetailView.swift
//  Recipe List App
//
//  Created by Christopher Ching on 2021-01-14.
//

import SwiftUI

struct RecipeDetailView: View {
    
    @Environment(\.presentationMode) var presentationMode
    
    var recipe:Recipe
    
    var gridItemLayout = [GridItem(.fixed(60), alignment: .leading), GridItem(.flexible(minimum: 200), alignment: .leading), GridItem(.fixed(100), alignment: .trailing)]

    @State var selectedServingSize = 2
    
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
                    
                    Spacer()
                    
                    // MARK: Rating Stars
                    RatingStarsView(rating: recipe.rating)
                        .padding(.trailing)
                }

                
                // MARK: Recipe summary
                Text(recipe.summary)
                    .padding(.top, 2)
                    .font(Font.custom("Avenir", size: 15))
                    
                HStack {
                   // MARK: Serving size picker
                    HStack {
                        Text("Wähle die Portionsgröße:")
                            .font(Font.custom("Avenir", size: 15))
                        Picker("", selection: $selectedServingSize) {
                            Text("0,5").tag(1)
                            Text("1,0").tag(2)
                            Text("1,5").tag(3)
                            Text("2,0").tag(4)
                        }
                        .font(Font.custom("Avenir", size: 15))
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width:160)
                    }
                    
                    Spacer()

                    // MARK: Recipe urlLink
                    Link("Link zum Rezept",
                         destination: URL(string: recipe.urlLink ?? "https://")!)
                        .padding(.top, 2)
                        .padding(.leading)
                        .font(Font.custom("Avenir Heavy", size: 15))
                }
                
                // MARK: Components
                VStack(alignment: .leading) {
                    Text("Komponenten")
                        .font(Font.custom("Avenir Heavy", size: 16))
                        .padding([.bottom, .top], 5)

                    LazyVGrid(columns: GlobalVariables.gridItemLayoutComponents, spacing: 6) {

                        ForEach (recipe.componentsArray.sorted(by: { $0.number < $1.number })) { component in
                            
                            VStack(alignment: .leading) {
                                
                                Text(component.name)
                                    .font(Font.custom("Avenir Heavy", size: 14))
                                    .padding([.bottom, .top], 5)
                                
                                VStack(alignment: .leading) {

                                    ForEach (component.ingredientsArray.sorted(by: { $0.number < $1.number })) { item in

                                        Text("• " + Rational.getPortion(unit:item.unit ?? "", weight:item.weight, num:item.num, denom:item.denom, targetServings: selectedServingSize) + item.name)
                                            .font(Font.custom("Avenir", size: 15))
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()
                
                // MARK: Instructions
                VStack(alignment: .leading) {
                    HStack {
                        Text("Verarbeitungsschritte:")
                            .font(Font.custom("Avenir Heavy", size: 16))
                            .padding([.bottom, .top], 5)
                        
                        Spacer()
                        
                        Text("Bearbeitungdauer: " + Rational.displayHoursMinutes(recipe.prepTime))
                            .font(Font.custom("Avenir", size: 16))
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
                    .font(Font.custom("Avenir", size: 16))
                        .padding([.bottom, .top], 5)
                }
            }
            .padding()
        }
        .navigationBarTitle(recipe.name)
    }
}
